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
		//var reactor = new grumpkin.poll.EpollPoller(1024, 512);
		//reactor.maxUpdatesPerSecond = 6000;
		//reactor.maxPendingConnections = 600;
		var protocol = new Test();

		protocol.listen("localhost", 12345);
		grumpkin.Reactor.reactor.run();
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
