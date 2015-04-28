package grumpkin;

import sys.net.Socket;
import haxe.io.Bytes;
#if neko
import neko.net.ThreadServer;
#else
import cpp.net.ThreadServer;
#end


typedef TestClient = {
    var sock:Socket;
}

class Test2 extends ThreadServer<TestClient, String>
{
	static function main()
	{
		var server = new Test2();
		server.maxSockPerThread = 256;
		server.run("localhost", 12345);
	}

	override public function run(host, port:Int)
	{
		trace("listening on " + host + ":" + port);
		super.run(host, port);
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
