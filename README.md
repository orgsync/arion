# Arion

> ARI′ON (Ariôn). A fabulous horse, which Poseidon begot by Demeter; for in
> order to escape from the pursuit of Poseidon, the goddess had metamorphosed
> herself into a mare, and Poseidon deceived her by assuming the figure of a
> horse. Demeter afterwards gave birth to the horse Arion, and a daughter
> whose name remained unknown to the uninitiated.
> — [Dictionary of Greek and Roman Biography and Mythology][DGRBM]

Born of [Demeter][] and [Poseidon][], [Arion][] will reliably speak to
[Kafka][] for you. Specifically, Arion provides an HTTP interface to the
official Kafka producer through a durable, disk-backed queue.

Arion supports Kafka 0.9.0.0 and 0.9.0.1, and requires Java 1.8.

## Installation

[![Docker Repository on Quay](https://quay.io/repository/orgsync/arion/status?token=b21afbe2-abaa-4e76-8aec-f37b3a03ece5 "Docker Repository on Quay")](https://quay.io/repository/orgsync/arion)

Arion can be run using Docker or built into a standalone jar using
`lein uberjar`.

## Configuration

Supply the following environment variables:

|  variable | default |  description |
|-----------|---------|--------------|
|`ARION_PORT` | `80` | http server port |
|`ARION_IDLE_TIMEOUT` | `15` | disconnect after specified seconds of no activity; 0 to disable |
|`ARION_FSYNC_PUT` | `true` | whether an fsync should be performed for each put |
|`ARION_FSYNC_TAKE` | `true` | whether an fsync should be performed for each take |
|`ARION_FSYNC_THRESHOLD` | | the maximum number of writes before an fsync |
|`ARION_FSYNC_INTERVAL` | | the maximum amount of time that can elapse before an fsync (ms) |
|`ARION_SLAB_SIZE` | `67108864` | the size of the backing files for the queue (bytes) |
|`ARION_QUEUE_PATH` | `/var/arion` | directory used by the durable queue to write slabs |
|`ARION_MAX_MESSAGE_SIZE` | `1000000` | maximum allowed message size in bytes |
|`KAFKA_BOOTSTRAP` | `localhost:9092` | addresses of initial Kafka brokers [(format)][boot] |
|`STATSD_HOST` | `localhost` | [StatsD][] metrics server host |
|`STATSD_PORT` | `8125` | [StatsD][] metrics server port |
| `HEAP_SIZE` | `200m` | allocated heap size (container only) |
| `MAX_PAUSE` | `100` | maximum GC pause time in ms (container only) |
| `JMX_PORT` | `3333` | JMX management port (container only) |
| `JMX_HOSTNAME` | `arion` | externally accessible host name (container only) |

Logs are written to `STDOUT`.

## Usage

Arion is designed to be running on the same machine as the processes
producing messages to prevent messages from being lost during network
interruptions. The number of Kafka partitions drives concurrency. Each
partition only has one message being sent or retried at any given time so
partition order is preserved.

Synchronous, asynchronous, and websocket message production are
supported:

### Synchronous Message Production

```
POST http://<host>:<port>/sync/<topic>[/key]
```

The URL is composed of the following components:

- `topic`: the Kafka topic to which the message should be sent. This must be
  a valid Kafka topic name.

- `key`: an optional key whose hash will determine the topic partition. If
  no key is provided, a random partition will be selected.

The body of the POST request will be sent byte-for-byte as the body of the
Kafka message.

Upon reception of the request, the message will be immediately written to the
disk-backed durable queue and flushed to disk, but a response will not be
returned until all in-sync replicas have confirmed receipt of the message.

If the operation fails (for example, if the Kafka broker cannot be reached),
the message will be retried until it succeeds, which means that the request
may be held open indefinitely if the idle timeout is disabled.

Example response:

```http
HTTP/1.1 201 Created
Content-Type: application/json
Server: Aleph/0.4.0
Connection: Keep-Alive
Date: Tue, 02 Feb 2016 23:31:10 GMT
content-length: 110
```

```js
{
  "status": "sent",
  "key": "mykey",
  "topic": "test",
  "partition": 0,
  "offset": 128158,
  "sent": "2016-02-02T23:30:45.447Z"
}
```

The response contains the topic and key, the partition the message was sent on,
the partition offset the message was written to, and the timestamp when the
message was confirmed by Kafka.

### Asynchronous Message Production

```
POST http://<host>:<port>/async/<topic>[/key]
```

Asynchronous requests accept identical parameters as synchronous requests.
However, rather than a response being returned after the message has been
ACKed by the Kafka brokers, a response is returned immediately after the
message has been enqueued and flushed to disk.

Example response:

```http
HTTP/1.1 202 Accepted
Content-Type: application/json
Server: Aleph/0.4.0
Connection: Keep-Alive
Date: Tue, 02 Feb 2016 23:31:46 GMT
content-length: 132
```

```js
{
  "status": "enqueued",
  "topic": "test",
  "key": "mykey",
  "enqueued": "2016-02-02T23:31:26.063Z",
  "id": "13ceb7f0-ca05-11e5-82e7-b44ee83bda87"
}
```

The response contains the topic, the key (if provided, `null` otherwise), the
timestamp when the message was enqueued, and an internal unique identifier
used to identify the message while it is being sent to Kafka. The partition
is not yet known because obtaining the partitions for a given topic may block
during Kafka failure.

### Websocket Message Production

```
GET ws://<host>:<port>/websocket/<topic>[/key]
```

Synchronous and asynchronous production offer clear guarantees, but at
the cost of additional overhead. When throughput is critical, websocket
production may be appropriate.

Websocket requests accept identical parameters as synchronous and
asynchronous requests. However, rather than returning a response body a
websocket connection is made. Messages sent to the socket are enqueued
and broadcasted to the given topic in the order in which they are sent,
optionally with a specified key.

After the message is acked by all in-sync replicas, a responses is
returned on the socket. Message responses are sent in the order in
which the messages were enqueued. It is possible to have hundreds of
un-acked requests in flight that have not been written to the durable
queue, so there is no guarantee that a request has been or ever will be
broadcasted to a topic partition until a response is received.

Like all connections, websockets are disconnected after
`ARION_IDLE_TIMEOUT` seconds of inactivity.

```
# wscat -c ws://arion/websocket/test
connected (press CTRL+C to quit)
> test1
< {"topic":"test","partition":7,"offset":0,"sent":"2016-09-09T00:24:45.387Z","status":"sent"}
> test2
< {"topic":"test","partition":6,"offset":0,"sent":"2016-09-09T00:24:53.507Z","status":"sent"}
> test1
< {"topic":"test","partition":1,"offset":0,"sent":"2016-09-09T00:25:00.183Z","status":"sent"}
disconnected
```

### Status

Arion also provides endpoints that report its status:

#### Statistics

```
GET http://<host>:<port>/stats
```

The `stats` endpoint provides information on the number of slabs the
persistent queue has allocated, the number of slabs currently in use, and the
number of items that have been enqueued, retried, completed, and currently in
progress. It also includes [metrics reported by the Kafka producer][metrics].

```js
{
  "queue": {
    "num-slabs": 1,
    "num-active-slabs": 1,
    "enqueued": 6,
    "retried": 0,
    "completed": 6,
    "in-progress": 0
  },
  "kafka": {
    "connection-count": 1,
    // ...
    "request-rate": 0
  }
}
```

#### Health Check

The health check will report success if the server is running, even if Kafka
cannot be reached, as asynchronous message requests will be unaffected.

```
<GET|HEAD> http://<host>:<port>/health-check
```

```js
{
  "status": "ok"
}
```

## Metrics

Arion periodically writes metrics using the [StatsD][] protocol to the server
specified in the `STATSD_HOST` and `STATSD_PORT` environment variables. The
`/stats` endpoint can also be used to read a subset of these metrics.

## License

Copyright 2016 OrgSync.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

[Arion]: https://en.wikipedia.org/wiki/Arion_(mythology)
[DGRBM]: http://www.theoi.com/Ther/HipposAreion.html
[Homer]: http://www.perseus.tufts.edu/hopper/text?doc=urn:cts:greekLit:tlg0012.tlg001.perseus-eng1:23.319-23.350
[Demeter]: https://en.wikipedia.org/wiki/Law_of_Demeter
[Poseidon]: https://github.com/bpot/poseidon
[Kafka]: http://kafka.apache.org
[boot]: http://kafka.apache.org/documentation.html#producerconfigs
[StatsD]: https://codeascraft.com/2011/02/15/measure-anything-measure-everything/
[metrics]: https://kafka.apache.org/090/javadoc/org/apache/kafka/clients/producer/Producer.html#metrics()
