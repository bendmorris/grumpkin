package grumpkin.protocol;

import haxe.io.Bytes;
import sys.net.Socket;
import sys.net.Host;


typedef MessageInfo<Message> = {
	var msg:Message;
	var bytes:Int;
}


class WebSocketProtocol<Client, Message> extends Protocol<Client, Message>
{
	public static inline var MAGIC_STRING = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

	static inline function hex2data(hex:String):String
	{
		var t = "";
		for( i in 0...Std.int( hex.length / 2 ) )
			t += String.fromCharCode(Std.parseInt("0x" + hex.substr(i * 2, 2)));
		return t;
	}

	static inline function encodeBase64(t:String):String
	{
		var suffix = switch( t.length % 3 )  {
			case 2 : "=";
			case 1 : "==";
			default : "";
		};
		return haxe.crypto.BaseCode.encode(t, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/") + suffix;
	}

	public function new()
	{
		super();
	}

	override public function addClient(s:Socket):Bool
	{
		s.setBlocking(false);

		var client = clientConnected(s);
		if (client == null)
		{
			return false;
		}

		var clientInfo:ClientInfo<Client> = {
			client: client,
			socket: s,
			buf: Bytes.alloc(initialBufferSize),
			bufpos: 0,
			custom: false,
		};
		s.custom = clientInfo;
		return true;
	}

	override function readClientData(c:ClientInfo<Client>):Void
	{
		var available = c.buf.length - c.bufpos;

		if (available == 0)
		{
			var newsize = c.buf.length * 2;
			if (newsize > maxBufferSize)
			{
				newsize = maxBufferSize;
				if( c.buf.length == maxBufferSize )
					throw "Max buffer size reached";
			}
			var newbuf = Bytes.alloc(newsize);
			newbuf.blit(0, c.buf, 0, c.bufpos);
			c.buf = newbuf;
			available = newsize - c.bufpos;
		}

		var bytes = c.socket.input.readBytes(c.buf, c.bufpos, available);
		var pos = 0;
		var len = c.bufpos + bytes;

		while (len >= 2)
		{
			var m:MessageInfo<Message> = null;
			if (c.custom)
			{
				// upgraded; read message
				m = readWebSocketMessage(c.client, c.buf, pos, len);
			}
			else
			{
				// look for HTTP upgrade request
				m = attemptUpgrade(c, pos, len);
			}

			if( m == null )
				break;
			pos += m.bytes;
			len -= m.bytes;
			clientMessage(c.client, m.msg);
		}
		if (pos > 0)
		{
			c.buf.blit(0, c.buf, pos, len);
		}
		c.bufpos = len;
	}

	function attemptUpgrade(client:ClientInfo<Client>, pos:Int, len:Int):MessageInfo<Message>
	{
		var buf = client.buf;
		var msg = buf.getString(pos, len);

		if (~/^GET (\/.*) HTTP\//.match(msg))
		{
			var response = checkHandshake(msg);
			if (response == null)
			{
				Reactor.reactor.stopClient(client.socket);
			}
			else
			{
				client.custom = true;
				client.socket.write(response);
				client.socket.output.flush();
				return {msg: null, bytes: len};
			}
		}
		else
		{
			Reactor.reactor.stopClient(client.socket);
		}
		return null;
	}

	inline function checkHandshake(msg:String):Null<String>
	{
		// HTTP GET request, may be websocket handshake attempt
		var upgrade = false;
		var key:Null<String> = null;
		var lines = msg.split('\r\n');
		lines.shift();
		for (line in lines)
		{
			var r = ~/^([a-zA-Z0-9\-]+): (.+)$/;
			if (line == "" || !r.match(line))
			{
				break;
			}
			switch (r.matched(1))
			{
				case "Sec-WebSocket-Key": key = r.matched(2);
				case "Upgrade": upgrade = true;
				default: {}
			}
		}

		if (!upgrade || key == null)
		{
			return null;
		}

		var keyResponse = encodeBase64(hex2data(haxe.crypto.Sha1.encode(StringTools.trim(key) + MAGIC_STRING)));
		var s = "HTTP/1.1 101 Switching Protocols\r\n"
			  + "Upgrade: websocket\r\n"
			  + "Connection: Upgrade\r\n"
			  + "Sec-WebSocket-Accept: " + keyResponse + "\r\n"
			  + "\r\n";

		return s;
	}

	function readWebSocketMessage(c:Client, buf:Bytes, pos:Int, len:Int):MessageInfo<Message>
	{
		var opcode = buf.get(0);
		var msgLength = buf.get(1);

		var final = opcode & 0x80 != 0;
		opcode = opcode & 0x0F;
		var mask = msgLength >> 7 == 1;
		msgLength = msgLength & 0x7F;

		var skip = 2;
		if (msgLength == 126)
		{
			if (len < 4) return null;
			skip += 2;
			msgLength = ((buf.get(2) & 0xFF) << 8) | (buf.get(3) & 0xFF);
		}
		else if (msgLength > 126)
		{
			if (len < 6) return null;
			skip += 8;
			msgLength = (buf.get(2) << 24) | (buf.get(3) << 16) | (buf.get(4) << 8) | buf.get(5);
		}

		if (len < skip + msgLength)
		{
			return null;
		}

		var msgData:Bytes;
		if (mask)
		{
			var maskKey = buf.sub(skip, 4);
			skip += 4;
			msgData = buf.sub(skip, msgLength);
			if (msgData.length < msgLength)
			{
				return null;
			}
			for (i in 0 ... msgData.length)
			{
				msgData.set(i, msgData.get(i) ^ maskKey.get(i % 4));
			}
		}
		else
		{
			msgData = buf.sub(skip, msgLength);
		}

		var m = readClientMessage(c, msgData, 0, msgLength);
		if (m == null) return null;
		return {msg: m.msg, bytes: skip + msgLength};
	}

	override public function write(socket:Socket, data:Bytes, pos:Int, length:Int)
	{
		socket.output.writeByte(130);
		if (length <= 125)
		{
			socket.output.writeByte(length);
		}
		else if (length < 0x10000)
		{
			socket.output.writeByte(126);
			socket.output.writeByte((length>>8) & 0xff);
			socket.output.writeByte(length & 0xff);
		}
		else
		{
			throw "WebSockets message too big!";
		}

		socket.output.writeFullBytes(data, pos, length);
		socket.output.flush();
	}
}
