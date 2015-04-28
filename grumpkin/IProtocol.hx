package grumpkin;

import sys.net.Socket;


interface IProtocol
{
	public var listener:Socket;

	public function listen(host:String, port:Int):Void;
	public function addClient(s:Socket):Bool;
	public function disconnectClient(s:Socket):Void;
	public function clientMessageReady(s:Socket):Void;
}
