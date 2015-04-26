package grumpkin;

import sys.net.Socket;
import haxe.io.Bytes;


typedef TestClient = {
    var sock:Socket;
}

class Test extends AsyncServer<TestClient, String>
{
	static function main()
	{
		var server = new Test();
		var loopTask = server.loopingCall(haxe.Log.trace.bind("This message will be traced every second for 5 seconds."), 1);
		server.callLater(haxe.Log.trace.bind("This message will be traced only once, after 3.5 seconds."), 3.5);
		server.callLater(function() {
			trace("Loop stopped. Server will shut down automatically in 60 seconds.");
			server.callLater(server.shutdown, 60);
			loopTask.stop();
		}, 5);
		server.callLater(server.defer.bind(function() { trace("Returning 2"); return 2; }, function(n:Int) trace("The answer is " + n)), 0);
		var poller = new grumpkin.poll.EpollPoller(1024, 128);
		server.run("localhost", 12345, poller);
	}

	override public function run(host, port:Int, ?poller)
	{
		trace("listening on " + host + ":" + port);
		super.run(host, port, poller);
	}

	override public dynamic function clientConnected(s:Socket):TestClient { return {sock: s}; }

	override public dynamic function clientDisconnected(c:TestClient) {}

	override public dynamic function readClientMessage(c:TestClient, buf:Bytes, pos:Int, len:Int):{msg:String, bytes:Int}
	{
		if (len > 1)
		c.sock.write("HTTP/1.1 200 OK\nContent-Type: text/xml; charset=utf-8\nContent-Length: 8\n\nabcdefgh");
		return {msg: null, bytes: len};
	}
}
