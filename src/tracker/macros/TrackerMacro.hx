package tracker.macros;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

@:allow(tracker.macros.EventsMacro)
@:allow(tracker.macros.ObservableMacro)
@:allow(tracker.macros.SerializableMacro)
class TrackerMacro {

    static var entityType:ComplexType = null;

    static var entityTypeStr:String = null;

    macro public function entity(type:String) {

        if (type != 'tracker.Entity')
            Compiler.define('tracker_custom_entity', type);

        var pack:Array<String>;
        var name:String;
        var dotLastIndex = type.lastIndexOf('.');
        if (dotLastIndex != -1) {
            pack = type.substr(0, dotLastIndex).split('.');
            name = type.substr(dotLastIndex + 1);
        }
        else {
            pack = [];
            name = type;
        }

        entityType = TPath({name: name, params: [], pack: pack});
        entityTypeStr = type;

        return null;
        
    }

    macro public function backend(type:String) {

        if (type != 'tracker.Backend') {
            Compiler.define('tracker_custom_backend', type);

            var pack:Array<String>;
            var name:String;
            var dotLastIndex = type.lastIndexOf('.');
            if (dotLastIndex != -1) {
                pack = type.substr(0, dotLastIndex).split('.');
                name = type.substr(dotLastIndex + 1);
            }
            else {
                pack = [];
                name = type;
            }

            Context.defineType({
                pack: ['tracker'],
                name: 'Backend',
                pos: Context.currentPos(),
                meta: [],
                params: [],
                fields: [],
                isExtern: false,
                kind: TDAlias(TPath({
                    name: name,
                    params: [],
                    pack: pack
                }))
            });
        }

        return null;
        
    }

}