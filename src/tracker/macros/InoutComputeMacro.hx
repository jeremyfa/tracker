package tracker.macros;

import haxe.macro.Context;
import haxe.macro.Expr;

using StringTools;

/**
 * Shared helper that transforms `@inout @compute` fields based on the direction
 * (in/out) detected via global defines or class metadata.
 *
 * Idempotent: can be called multiple times on the same fields without side effects.
 * Must be called from ObservableMacro.build(), SerializableMacro.build() and
 * EntityMacro.build() so that whichever runs first does the transformation and
 * the others see the already-processed fields (or skip immediately).
 *
 * The feature is fully inactive unless one of these defines is set:
 *   -D tracker_compute_inout
 *   -D tracker_compute_in
 *   -D tracker_compute_out
 */
class InoutComputeMacro {

    public static function processFields(
        fields:Array<Field>,
        classMetas:Metadata,
        pos:Position
    ):Void {

        // Opt-in: skip entirely if no activation define is set
        #if (!tracker_compute_inout && !tracker_compute_in && !tracker_compute_out)
        return;
        #end

        var direction = detectDirection(classMetas);
        if (direction == None) return;

        var fieldsToAdd:Array<Field> = [];

        for (field in fields) {
            // Single-pass check: candidate is @inout @compute AND not yet processed
            if (!isUnprocessedInoutCompute(field)) continue;

            // Mark as processed (idempotence) — only on @inout @compute fields
            field.meta.push({ name: ':inoutProcessed', params: [], pos: pos });

            switch field.kind {
                case FFun(f):
                    var fieldName = field.name;
                    var returnType = f.ret;
                    var outFieldName = '_out_' + fieldName;

                    fieldsToAdd.push(makeOutField(outFieldName, returnType, pos));

                    if (direction == Out) {
                        // Keep the original body. Inject an @autorun method that propagates
                        // the computed value to the _out_* field. EntityMacro will register
                        // it in the constructor + _autorunMarkedMethods automatically.
                        fieldsToAdd.push(makeShareAutorunField(fieldName, outFieldName, pos));
                    }
                    else { // In
                        // Discard the original body entirely. Replace the function with a
                        // read-only property whose getter inlines a direct read of _out_<name>.
                        //
                        // The resulting API matches the @computeOut side (uniform `model.foo`,
                        // no parentheses) but without the overhead of going through the @compute
                        // machinery (no extra unobservedFoo cache, no extra autorun layer).
                        //
                        // The original body is gone — it's not present in the generated code,
                        // which is the whole point: IP protection on the receiver side.
                        field.kind = FProp('get', 'never', returnType);
                        // Drop @compute (and @inout) so ObservableMacro / other macros leave
                        // this field alone — it's now a plain Haxe property.
                        field.meta = field.meta.filter(m -> m.name != 'compute' && m.name != 'inout');
                        // Inject the getter implementation.
                        fieldsToAdd.push(makeInGetterField(fieldName, outFieldName, returnType, pos));
                    }

                default:
                    Context.error("@inout @compute can only be applied to functions", field.pos);
            }
        }

        for (f in fieldsToAdd) fields.push(f);

    }

    static function detectDirection(classMetas:Metadata):Direction {

        #if tracker_compute_out
        return Out;
        #elseif tracker_compute_in
        return In;
        #else
        for (m in classMetas) {
            if (m.name == 'computeOut') return Out;
            if (m.name == 'computeIn') return In;
        }
        return None;
        #end

    }

    static function isUnprocessedInoutCompute(field:Field):Bool {

        if (field.meta == null) return false;
        var hasCompute = false;
        var hasInout = false;
        var hasProcessed = false;
        for (m in field.meta) {
            if (m.name == 'compute') hasCompute = true;
            else if (m.name == 'inout') hasInout = true;
            else if (m.name == ':inoutProcessed') hasProcessed = true;
        }
        return hasCompute && hasInout && !hasProcessed;

    }

    static function makeOutField(name:String, type:ComplexType, pos:Position):Field {

        // No :inoutProcessed marker here — this generated field doesn't have
        // @inout @compute so the helper will never consider it a candidate again.
        return {
            pos: pos,
            name: name,
            kind: FVar(type, null),
            access: [APublic],
            meta: [
                { name: 'serialize', params: [], pos: pos },
                { name: ':noCompletion', params: [], pos: pos }
            ],
            doc: null
        };

    }

    static function makeInGetterField(fieldName:String, outFieldName:String, returnType:ComplexType, pos:Position):Field {

        // Generates: @:noCompletion inline private function get_<fieldName>():<returnType> return _out_<fieldName>;
        return {
            pos: pos,
            name: 'get_' + fieldName,
            kind: FFun({
                args: [],
                ret: returnType,
                expr: macro return $i{outFieldName}
            }),
            access: [APrivate, AInline],
            meta: [
                { name: ':noCompletion', params: [], pos: pos }
            ],
            doc: null
        };

    }

    static function makeShareAutorunField(fieldName:String, outFieldName:String, pos:Position):Field {

        // Generates:
        //   @autorun @:noCompletion private function _share_out_<fieldName>():Void {
        //       var result = this.<fieldName>;
        //       tracker.Autorun.unobserve();
        //       this.<outFieldName> = result;
        //       tracker.Autorun.reobserve();
        //   }
        return {
            pos: pos,
            name: '_share_out_' + fieldName,
            kind: FFun({
                args: [],
                ret: macro :Void,
                expr: macro {
                    var result = this.$fieldName;
                    tracker.Autorun.unobserve();
                    this.$outFieldName = result;
                    tracker.Autorun.reobserve();
                }
            }),
            access: [APrivate],
            meta: [
                { name: 'autorun', params: [], pos: pos },
                { name: ':noCompletion', params: [], pos: pos }
            ],
            doc: null
        };

    }

}

private enum Direction {
    None;
    Out;
    In;
}
