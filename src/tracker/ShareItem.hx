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

#if tracker_share_item_struct typedef ShareItem = #else @:structInit class ShareItem #end {

    public var id:String;

    public var action:ShareItemAction;

    public var type:String = null;

    public var props:DynamicAccess<String> = null;

}
