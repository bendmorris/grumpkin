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

Multiple protocols can be told to listen on different host/port combinations 
before running the reactor. `reactor.run()` will begin the event loop, which 
will block until the reactor is shut down.

By default, `select` is used to check for socket events. The first reactor 
instance created will become the global reactor, so to use an alternate reactor:

    var maxConnections = 1024;
    var maxConnections = 128;
    var reactor = new grumpkin.reactor.EpollReactor(maxConnections, maxEvents);
    
    protocol.listen(host, port);
    reactor.run();

Make sure you create this reactor before trying to access the global 
Reactor.reactor variable, or the default SelectReactor will be created instead.

Additional features
-------------------

Some additional features:

    // call a function every 5 seconds
    reactor.loopingCall(function() { trace("It's been five seconds!"); }, 5);
    
    // call a function 30 seconds from now
    reactor.callLater(server.shutdown, 30);

Because grumpkin is single-threaded, you should avoid operations which block for 
extended periods of time, as they will prevent the server from receiving new 
connections, reading messages, etc. Send long operations to separate threads 
using `work` instead.
    
    // run a function in a separate worker thread
    reactor.work(f);

You can also perform work which returns a result, and process that result in the 
main reactor event loop:

    var f = function() return "this is the result";
    var onSuccess = function(result:Dynamic) trace(result);

    reactor.defer(f, onSuccess);
