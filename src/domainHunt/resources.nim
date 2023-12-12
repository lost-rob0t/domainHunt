import httpclient, deques, asyncdispatch
type
  ResourcePool*[T] = ref object
    resources: Deque[T]
    queuers: Deque[Future[T]]

  AsyncHttpClientPool* = ResourcePool[AsyncHttpClient]
  HttpClientPool* = ResourcePool[HttpClient]

proc dequeue*[T](pool: ResourcePool[T]): Future[T] =
  result = newFuture[T]("dequeue")
  if pool.resources.len == 0:
    pool.queuers.addLast result
  else:
    result.complete pool.resources.popFirst()

proc enqueue*[T](pool: ResourcePool[T], item: T) =
  if pool.queuers.len > 0:
    let fut = pool.queuers.popFirst()
    fut.complete(item)
  else:
    pool.resources.addLast(item)

proc newAsyncHttpClientPool*(size: int): AsyncHttpClientPool =
  result.new()
  for i in 1..size: result.enqueue(newAsyncHttpClient())

proc newHttpClientPool*(size: int): HttpClientPool =
  result.new()
  for i in 1..size: result.enqueue(newHttpClient())




template withPool*[T](pool: ResourcePool[T], body: untyped) {.dirty.} =
  ## A Simple abstraction manage a resource pool.
  var resource = waitFor pool.dequeue()
  try:
    body
  finally:
    pool.enqueue(resource)



when isMainModule:
  var pool = newHttpClientPool(10)
  pool.withPool():
    echo resource.getContent("https://google.com")
