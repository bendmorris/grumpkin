package grumpkin;

import haxe.io.Bytes;
import sys.net.Socket;


typedef ClientInfo<Client> = {
	var client:Client;
	var socket:Socket;
	var buf:Bytes;
	var bufpos:Int;
	var custom:Dynamic;
}
