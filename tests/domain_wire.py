"""Actual installed DomainHunt actor: canonical Scope/Target, WebSocket evidence, broker publication."""
import asyncio
import hashlib
import json
from pathlib import Path
import queue
import select
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zmq
from websockets.asyncio.server import serve

binary=str(Path(sys.argv[1]).resolve());broker_binary=str(Path(sys.argv[2]).resolve())
deliveries=[];websocket_errors=[]
packets=queue.Queue();server_ready=threading.Event();server_stop=threading.Event();endpoint={}
async def connection(websocket):
    try:
        while not server_stop.is_set():
            try:packet=packets.get_nowait()
            except queue.Empty:packet=json.dumps({'message_type':'heartbeat'})
            await websocket.send(packet)
            if 'certificate_update' in packet:deliveries.append(str(websocket.id))
            # The retained actor polls its broker for 500 ms per stream frame.
            # Heartbeats must not create an artificial certificate backlog.
            await asyncio.sleep(.6)
    except Exception as error:websocket_errors.append(str(error))
async def websocket_server():
    async with serve(connection,'127.0.0.1',0) as server:
        endpoint['url']=f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}/'
        server_ready.set()
        while not server_stop.is_set():await asyncio.sleep(.05)
thread=threading.Thread(target=lambda:asyncio.run(websocket_server()),daemon=True);thread.start()
assert server_ready.wait(5)
def address():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return f'tcp://127.0.0.1:{s.getsockname()[1]}'
api_address,pub_address=address(),address()
context=zmq.Context()
api=context.socket(zmq.DEALER);api.setsockopt(zmq.IDENTITY,b'test-publisher')
api.setsockopt(zmq.RCVTIMEO,5000);api.setsockopt(zmq.SNDTIMEO,5000);api.connect(api_address)
subscriber=context.socket(zmq.SUB);subscriber.setsockopt(zmq.SUBSCRIBE,b'domain')
subscriber.setsockopt(zmq.RCVTIMEO,10000);subscriber.connect(pub_address)
processes=[]
def stop(process):
    if process.poll() is None:
        process.terminate()
        try:process.wait(timeout=5)
        except subprocess.TimeoutExpired:process.kill();process.wait(timeout=5)
try:
    with tempfile.TemporaryDirectory() as directory:
        broker=subprocess.Popen([broker_binary,'--apiAddress='+api_address,'--pubAddress='+pub_address],
                                stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,cwd=directory)
        processes.append(broker)
        def send(event,value,topic=b'certstream'):
            api.send_multipart([b'',b'SC01',b'test-publisher',b'fixture:message',str(int(time.time())).encode(),
                                str(event).encode(),topic,json.dumps(value).encode()])
            return api.recv_multipart()
        assert send(7,'',b'test')==[b'1']
        actor=subprocess.Popen([binary,'--apiAddress='+api_address,'--subAddress='+pub_address,'--webSocketAddr='+endpoint['url']],
                               stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=directory,bufsize=0)
        processes.append(actor)
        deadline=time.monotonic()+15
        while True:
            ready,_,_=select.select([actor.stdout],[],[],max(0,deadline-time.monotonic()))
            assert ready,'actor did not register with the broker'
            line=actor.stdout.readline().decode().strip()
            assert actor.poll() is None,(line,actor.stderr.read().decode())
            if line=='connected....':break
        time.sleep(.3)
        scope={'id':'scope:fixture','dataset':'test','dtype':'scope','schemaVersion':'0.10.1','name':'Fixture',
               'inScope':[r'\.example\.test$'],'outOfScope':[r'^blocked\.']}
        target={'id':'target:fixture','dataset':'test','dtype':'target','schemaVersion':'0.10.1',
                'actor':'certstream','target':'example.test','options':{'scope':scope},
                'scope':{'schema':'org.starintel/core@1/scope','id':scope['id']}}
        assert send(8,target)==[b'1']
        time.sleep(.3)
        observation={'message_type':'certificate_update','data':{'leaf_cert':{'all_domains':['api.example.test','blocked.example.test','outside.test']},
                     'unknown':{'flag':False,'nil':None,'items':[]},'source':{'name':'fixture','url':'https://example.test/'}}}
        wire=json.dumps(observation,indent=2)
        packets.put(wire)
        document=json.loads(subscriber.recv_multipart()[-1])
        assert document['schemaVersion']=='0.10.1' and document['dtype']=='domain' and document['dataset']=='test'
        assert document['name']=='api.example.test' and document['id']==hashlib.md5(b'api.example.test').hexdigest()
        assert document['raw']==observation and document['rawContent']==wire
        assert document['extensions']['domainHunt']=={'targetId':target['id'],'scope':scope}
        assert '_id' not in document and 'data' not in document
        assert not subscriber.poll(200),'excluded domain was published'
        # Invalid options must not replace/add active matcher state.
        malformed={**target,'id':'target:invalid','options':{'scope':{**scope,'id':'scope:bad','inScope':[17]}}}
        assert send(8,malformed)==[b'1']
        time.sleep(.3)
        packets.put(wire)
        assert json.loads(subscriber.recv_multipart()[-1])==document
        assert not subscriber.poll(200),'invalid configuration added another scan'
        # Reject a whole malformed certificate observation before any partial output.
        malformed_observation={**observation,'data':{'leaf_cert':{'all_domains':['api.example.test',17]}}}
        packets.put(json.dumps(malformed_observation))
        assert not subscriber.poll(300),'malformed observation was partially published'
        assert actor.poll() is None,'actor did not retain its retry/reconnect loop'
        assert send(8,{**target,'schemaVersion':'0.10.2'})==[b'2']
    print('actual installed DomainHunt: generated Scope/Target, real WebSocket/ZeroMQ, include/exclude precedence, stable identity, exact raw evidence, invalid configuration and observation rejection PASS')
finally:
    failed=sys.exc_info()[0] is not None
    if failed:print({"deliveries":deliveries,"websocketErrors":websocket_errors},file=sys.stderr)
    for process in reversed(processes):
        stop(process)
        if failed:
            if process.stdout is not None:print(process.stdout.read().decode()[-4000:],file=sys.stderr)
            if process.stderr is not None:print(process.stderr.read().decode()[-4000:],file=sys.stderr)
    api.close(linger=0);subscriber.close(linger=0);context.term()
    server_stop.set();thread.join(timeout=5)
