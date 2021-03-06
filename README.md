**grumpkin** is an asynchronous server, written in Haxe, which can run on the 
Neko VM or compiled to C++. It can be used as a single-threaded alternative to 
the built-in ThreadServer.

The API of grumpkin is very similar to neko.net.ThreadServer.

Getting started
---------------

To run the test server:

    haxe test.hxml && neko test.n

Grumpkin uses the [reactor 
pattern](https://en.wikipedia.org/wiki/Reactor_pattern). A server consists of 
two parts: the **protocol**, which is responsible for reading messages and 
storing client data, and the **reactor**, which stores sockets, accepts new 
connections and notifies the protocol when new clients or messages are 
available.

To customize the server, create your own protocol class which extends 
`grumpkin.Protocol<Client, Message>`. Client is the type which will be used for 
client data, and Message is the type for messages you will generate after 
reading from sockets. At minimum, your protocol should implement the 
clientConnected and clientMessage functions to return a Client after a 
successful connection and a Message after reading a complete message.

To start, tell your protocol to listen for new connections:

    protocol.listen(host, port);

...and start the reactor:

    var reactor = grumpkin.Reactor.reactor;
    reactor.run();

![starting the reactor](http://i.imgur.com/BnZFqSc.jpg)

(At this point please warn anyone nearby: "HOLD ON, I'M STARTING THE REACTOR!!")

Multiple protocols can be told to listen on different host/port combinations 
before running the reactor. `reactor.run()` will begin the event loop, which 
will block until the reactor is shut down.

By default, `select` is used to check for socket events. The first reactor 
instance created will become the global reactor, so to use an alternate reactor:

    var maxConnections = 1024;
    var reactor = new grumpkin.reactor.EpollReactor(maxConnections);
    
    protocol.listen(host, port);
    reactor.run();

Make sure you create this reactor before trying to access the global 
Reactor.reactor variable, or the default SelectReactor will be created instead.

Additional features
-------------------

Any object that implements the "IUpdater" interface can be added to the
reactor's update loop, which will call the object's "update" method every cycle.
Examples of using builtin IUpdater types include reactor.loopingCall and
reactor.callLater:

    // call a function every 5 seconds
    reactor.loopingCall(function() { trace("It's been five seconds!"); }, 5);
    
    // call a function 30 seconds from now
    reactor.callLater(server.shutdown, 30);

The update method's return value will determine whether it should remain in the 
update loop (`true`) or be removed (`false`).

There are no guarantees about how long each cycle of the event loop may take (if
there are no updaters ready to act, the reactor will block waiting for new
socket events) so the update method should check how much time has elapsed since
last being called if necessary. An updater can use the "nextUpdate" property to
signal the maximum amount of time to wait before it should be called by the
reactor.

Because grumpkin is single-threaded, you should avoid operations which block for
extended periods of time, as they will prevent the event loop from continuing.
This will block the server from receiving new connections, reading messages,
updating IUpdater objects, etc. Send long operations to separate threads using
`work` instead.
    
    // run a function in a separate worker thread
    reactor.work(f);

You can also perform work which returns a result, and process that result in the 
main reactor event loop:

    var f = function() return "this is the result";
    var onSuccess = function(result:Dynamic) trace(result);
    var onError = function(error:Dynamic) logError("OH NO! An error occurred", error);

    reactor.defer(f, onSuccess, onError);
