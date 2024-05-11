package tracker;

import haxe.DynamicAccess;

enum abstract ShareItemAction(Int) from Int to Int {

    var SET = 0;

    var UPDATE = 1;

    var DESTROY = 2;

    public function toString():String {
        return switch abstract {
            case SET: 'SET';
            case UPDATE: 'UPDATE';
            case DESTROY: 'DESTROY';
        }
    }

}

@:structInit
class ShareItem {

    public var id:String;

    public var action:ShareItemAction;

    public var type:String = null;

    public var props:DynamicAccess<String> = null;

}
