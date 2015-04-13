package grumpkin;

import sys.net.Socket;
import haxe.io.Bytes;


class Test extends AsyncServer<String, String>
{
	static function main()
	{
		var server = new Test();
		var loopTask = server.loopingCall(haxe.Log.trace.bind("This message will be traced every second for 5 seconds."), 1);
		server.callLater(haxe.Log.trace.bind("This message will be traced only once, after 3.5 seconds."), 3.5);
		server.callLater(function() {
			trace("Loop stopped. Server will shut down automatically in 10 seconds.");
			server.callLater(server.shutdown, 10);
			loopTask.stop();
		}, 5);
		server.callLater(server.defer.bind(function() { trace("Returning 2"); return 2; }, function(n:Int) trace("The answer is " + n)), 0);
		server.run("localhost", 12345);
	}

	override public function run(host, port:Int, ?poller)
	{
		trace("listening on " + host + ":" + port);
		super.run(host, port, poller);
	}

	override public dynamic function clientConnected(s:Socket):String { trace("connected"); return "client"; }

	override public dynamic function clientDisconnected(c:String) { trace("disconnected"); }

	override public dynamic function readClientMessage(c:String, buf:Bytes, pos:Int, len:Int):{msg:String, bytes:Int}
	{
		trace(buf);
		return {
			msg : "here's a message",
			bytes : len,
		};
	}
}
