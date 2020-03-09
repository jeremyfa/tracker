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

    static var definedTypes:Map<String,Bool> = new Map();

    macro public function setEntity(type:String) {

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

        if (type != 'tracker.Entity' && !definedTypes.exists(type)) {
            definedTypes.set(type, true);
            Context.defineType({
                pack: ['tracker'],
                name: 'Entity',
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

    macro public function setComponent(type:String) {

        if (type != 'tracker.Component') {
            Compiler.define('tracker_custom_component', type);

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
            
            if(!definedTypes.exists(type)) {
                definedTypes.set(type, true);
                Context.defineType({
                    pack: ['tracker'],
                    name: 'Component',
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
        }

        return null;
        
    }

    macro public function setBackend(type:String) {

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

            if(!definedTypes.exists(type)) {
                definedTypes.set(type, true);
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
        }

        return null;
        
    }

    macro public function setArrayPool(type:String) {

        if (type != 'tracker.ArrayPool') {
            Compiler.define('tracker_custom_array_pool', type);

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

            if(!definedTypes.exists(type)) {
                definedTypes.set(type, true);
                Context.defineType({
                    pack: ['tracker'],
                    name: 'ArrayPool',
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
        }

        return null;
        
    }

    macro public function setReusableArray(type:String) {

        if (type != 'tracker.ReusableArray') {
            Compiler.define('tracker_custom_reusable_array', type);

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

            if(!definedTypes.exists(type)) {
                definedTypes.set(type, true);
                Context.defineType({
                    pack: ['tracker'],
                    name: 'ReusableArray',
                    pos: Context.currentPos(),
                    meta: [],
                    params: [{
                        name: 'T'
                    }],
                    fields: [],
                    isExtern: false,
                    kind: TDAlias(TPath({
                        name: name,
                        params: [TPType(macro :T)],
                        pack: pack
                    }))
                });
            }
        }

        return null;
        
    }

}