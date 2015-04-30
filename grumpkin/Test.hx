package grumpkin;

import sys.net.Socket;
import haxe.io.Bytes;


typedef TestClient = {
	var sock:Socket;
}

class Test extends Protocol<TestClient, String>
{
	static function main()
	{
		//var reactor = new grumpkin.reactor.SelectReactor(1024);
		//var reactor = new grumpkin.reactor.PollReactor(1024);
		var reactor = new grumpkin.reactor.EpollReactor(1024, 1024);
		reactor.maxPendingConnections = 128;

		var protocol = new Test();

		protocol.listen("localhost", 12345);
		reactor.callLater(reactor.stop, 20);
		reactor.run();
	}

	override public function listen(host:String, port:Int)
	{
		trace("listening on " + host + ":" + port);
		super.listen(host, port);
	}

	override public dynamic function clientConnected(s:Socket):TestClient { return {sock: s}; }

	override public dynamic function clientDisconnected(c:TestClient) {}

	override public dynamic function readClientMessage(c:TestClient, buf:Bytes, pos:Int, len:Int):{msg:String, bytes:Int}
	{
		c.sock.write("HTTP/1.1 200 OK\nContent-Type: text/xml; charset=utf-8\nContent-Length: 8\n\nabcdefgh");
		return {msg: null, bytes: len};
	}
}
