package tracker;

class Utils {

    /** Generate an uniform list of the requested size,
        containing values uniformly repartited from frequencies.
        @param values the values to put in list
        @param probabilities the corresponding probability for each value
        @param size the size of the final list */
    public static function uniformFrequencyList(values:Array<Int>, frequencies:Array<Float>, size:Int):Array<Int> {

        var list:Array<Int> = [];
        var pickValues:Array<Float> = [];

        for (i in 0...values.length) {
            pickValues[i] = 0;
        }

        // Set initial pick values
        for (i in 0...frequencies.length) {
            pickValues[i] += frequencies[i];
        }

        for (index in 0...size) {
            // Pick a value
            var bestPick = 0;
            var bestPickValue = 0.0;
            for (i in 0...values.length) {
                var pickValue = pickValues[i];
                if (pickValue > bestPickValue) {
                    bestPick = i;
                    bestPickValue = pickValue;
                }
            }

            // Add value
            list.push(values[bestPick]);
            pickValues[bestPick] -= 1.0;

            // Increment pick values
            for (i in 0...frequencies.length) {
                pickValues[i] += frequencies[i];
            }
        }

        return list;

    }

    static var _nextUniqueIntCursor:Int = 0;
    static var _nextUniqueInt0:Int = Std.int(Math.random() * 0x7ffffffe);
    static var _nextUniqueInt1:Int = Std.int(Date.now().getTime() * 0.0001);
    static var _nextUniqueInt2:Int = Std.int(Math.random() * 0x7ffffffe);
    static var _nextUniqueInt3:Int = Std.int(Math.random() * 0x7ffffffe);

    #if (cpp || cs || sys)
    static var _uniqueIdMutex:sys.thread.Mutex = new sys.thread.Mutex();
    #end

    /** Provides an identifier which is garanteed to be unique on the current session.
        It however doesn't garantee that this identifier is not predictable. */
    public static function uniqueId():String {

        #if (cpp || cs || sys)
        _uniqueIdMutex.acquire();
        #end

        switch (_nextUniqueIntCursor) {
            case 0:
                _nextUniqueInt0 = (_nextUniqueInt0 + 1) % 0x7fffffff;
            case 1:
                _nextUniqueInt1 = (_nextUniqueInt1 + 1) % 0x7fffffff;
            case 2:
                _nextUniqueInt2 = (_nextUniqueInt2 + 1) % 0x7fffffff;
            case 3:
                _nextUniqueInt3 = (_nextUniqueInt3 + 1) % 0x7fffffff;
        }
        _nextUniqueIntCursor = (_nextUniqueIntCursor + 1) % 4;

        var result = base62Id(_nextUniqueInt0) + '-' + base62Id() + '-' + base62Id(_nextUniqueInt1) + '-' + base62Id() + '-' + base62Id(_nextUniqueInt2) + '-' + base62Id() + '-' + base62Id(_nextUniqueInt3);

        #if (cpp || cs || sys)
        _uniqueIdMutex.release();
        #end

        return result;

    }

    inline public static function base62Id(?val:Null<Int>):String {

        // http://www.anotherchris.net/csharp/friendly-unique-id-generation-part-2/#base62
        // Haxe snippet from Luxe

        if (val == null) {
            val = Std.int(Math.random() * 0x7ffffffe);
        }

        inline function toChar(value:Int):String {
            if (value > 9) {
                var ascii = (65 + (value - 10));
                if (ascii > 90) { ascii += 6; }
                return String.fromCharCode(ascii);
            } else return Std.string(value).charAt(0);
        }

        var r = Std.int(val % 62);
        var q = Std.int(val / 62);
        if (q > 0) return base62Id(q) + toChar(r);
        else return Std.string(toChar(r));

    }

    public static function encodeChangesetData(data:String):String {

        return data.length + ':' + data;

    }

    public static function decodeChangesetData(rawData:String) {

        var serializedMap:Map<String,{ id:String, type:String, props:Dynamic }> = new Map();
        var rootInfo = null;

        // Reload an array of all changesets
        var changesetData:Array<String> = [];

        // TODO handle corrupted saves?

        while (true) {
            var colonIndex = rawData.indexOf(':');
            if (colonIndex == -1) break;

            var len = Std.parseInt(rawData.substr(0, colonIndex));
            var dataPart:String = rawData.substr(colonIndex + 1, len);
            changesetData.push(dataPart);

            rawData = rawData.substr(colonIndex + 1 + len);
        }

        // Reconstruct the mapping
        var i = changesetData.length - 1;
        while (i >= 0) {
            var data = changesetData[i];

            if (i == 0) {
                var u = new haxe.Unserializer(data);

                // Get root object info
                rootInfo = u.unserialize();

                // Update serialized map
                var changesetSerializedMap:Map<String,{ id:String, type:String, props:Dynamic }> = u.unserialize();
                for (item in changesetSerializedMap) {
                    var id = item.id;
                    if (!serializedMap.exists(id)) {
                        serializedMap.set(id, item);
                    }
                }
            }
            else {
                var u = new haxe.Unserializer(data);

                // Update serialized map
                var toAppend:Array<{ id:String, type:String, props:Dynamic }> = u.unserialize();
                for (item in toAppend) {
                    var id = item.id;
                    if (!serializedMap.exists(id)) {
                        serializedMap.set(id, item);
                    }
                }
            }

            i--;
        }

        return {
            serialized: rootInfo,
            serializedMap: serializedMap
        };

    }

}