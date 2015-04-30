package grumpkin;


interface IUpdater
{
	// return true if the object should keep updating, false otherwise
	public function update():Bool;
	// amount of time until next call; if indeterminate, should return 0
	public var nextUpdate(get, never):Null<Float>;
}
