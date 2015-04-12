**grumpkin** is an asynchronous server, written in Haxe, which can run on the 
Neko VM or compiled to C++. It can be used as a single-threaded alternative to 
the built-in ThreadServer.

The API of grumpkin is very similar to neko.net.ThreadServer.

Getting started
---------------

To run the test server:

    haxe test.hxml && neko test.n

To customize the server, create your own server class which extends 
`grumpkin.AsyncServer<Client, Message>`. Client is the type which will be used 
for client data, and Message is the type for messages you will generate after 
reading from sockets (String, ByteArray...)

At minimum, your server should implement the clientConnected and clientMessage 
functions to return a Client after a successful connection and a Message after 
reading a complete message.

To start your server:

    server.run(host, port);

By default, select is used to check for socket events. To use an alternative 
poller:

    var maxConnections = 1024;
    var poller = new grumpkin.poll.PollPoller(maxConnections);
    server.run(host, port, poller);

Additional features
-------------------

Some additional features:

    // call a function every 5 seconds
    server.loopingCall(function() { trace("It's been five seconds!"); }, 5);
    
    // call a function 30 seconds from now
    server.callLater(server.shutdown, 30);

Because grumpkin is single-threaded, you should avoid operations which block for 
extended periods of time, as they will prevent the server from receiving new 
connections, reading messages, etc. Send long operations to separate threads 
using `work` instead.
    
    // run a function in a separate worker thread
    server.work(f);
