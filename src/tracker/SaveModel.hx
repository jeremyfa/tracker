package tracker;

import tracker.Tracker.backend;
import haxe.crypto.Md5;

class SaveModel {

    static var BACKUP_NUM_STEPS:Int = 20000;

    static var NUM_BACKUPS:Int = 4;

    static var BACKUP_STEPS:Array<Int> = null;

    static var busyKeys:Array<String> = [];

/// Public API

    public static function getSavedOrCreate<T:Model>(modelClass:Class<T>, key:String, ?args:Array<Dynamic>):T {

        // Create new instance
        var instance = Type.createInstance(modelClass, args != null ? args : []);

        // Load saved data
        loadFromKey(instance, key);

        return instance;

    }

    public static function isBusyKey(key:String):Bool {

        return busyKeys.indexOf(key) != -1;

    }

    /** Load data from the given key. */
    public static function loadFromKey(model:Model, key:String):Bool {

        if (busyKeys.indexOf(key) != -1) {
            throw 'Cannot load data from key $key because some work is being done on it';
        }

        //initBackupLogicIfNeeded(key);

        var rawId = backend.readString('save_id_1_' + key);
        var id = rawId != null ? Std.parseInt(rawId) : -1;
        if (id != 1 && id != 2) {
            rawId = backend.readString('save_id_2_' + key);
            id = rawId != null ? Std.parseInt(rawId) : -1;
        }

        var data:String = null;

        if (id != 1 && id != 2) {
            backend.warning('Failed to load save from key: $key (no existing save?)');
        }
        else {
            data = backend.readString('save_data_' + id + '_' + key);
            if (data == null) {
                backend.warning('Failed to load save from key: $key/$id (corrupted save, try backups?)');
            }
        }

        #if sys
        // On sys targets, try to load from backup if nothing else worked
        if (data == null) {
            var storageDir = backend.storageDirectory();
            if (storageDir != null) {
                // Retrieve keys
                var backupHash = Md5.encode('backup ~ ' + key);
                var backupKey1 = 'backup_1_' + backupHash;
                var backupKey2 = 'backup_2_' + backupHash;

                try {
                    // Try backup 1
                    var dataPath = backend.pathJoin([storageDir, backupKey1]);
                    if (sys.FileSystem.exists(dataPath) && !sys.FileSystem.isDirectory(dataPath)) {
                        var backupData = sys.io.File.getContent(dataPath);
                        if (backupData != null) {
                            data = decodeHashedString(backupData);
                        }
                    }

                    if (data == null) {
                        // Try backup 2
                        dataPath = backend.pathJoin([storageDir, backupKey2]);
                        if (sys.FileSystem.exists(dataPath) && !sys.FileSystem.isDirectory(dataPath)) {
                            var backupData = sys.io.File.getContent(dataPath);
                            if (backupData != null) {
                                data = decodeHashedString(backupData);
                            }
                        }
                    }
                }
                catch (e:Dynamic) {
                    backend.error('Failed to load backup: $e');
                }
            }
        }
        #end

        return SerializeModel.loadFromData(model, data);

    }
    public static function autoSaveAsKey(model:Model, key:String, appendInterval:Float = 1.0, compactInterval:Float = 60.0) {

        var serializer = model.serializer;
        if (serializer == null) {
            serializer = new SerializeModel();
            serializer.checkInterval = appendInterval;
            serializer.compactInterval = compactInterval;
        }
        else if (serializer.checkInterval != appendInterval || serializer.compactInterval != compactInterval) {
            backend.warning('A serializer is already assigned with different appendInterval and compactInterval');
        }

        var saveDataKey1 = 'save_data_1_' + key;
        var saveDataKey2 = 'save_data_2_' + key;
        var saveIdKey1 = 'save_id_1_' + key;
        var saveIdKey2 = 'save_id_2_' + key;

        #if sys
        var backupHash = Md5.encode('backup ~ ' + key);
        var backupKey1 = 'backup_1_' + backupHash;
        var backupKey2 = 'backup_2_' + backupHash;
        #end

        // Start listening for changes to save them
        serializer.onChangeset(model, function(changeset) {

            // Mark this key as busy
            busyKeys.push(key);

            if (changeset.append) {

                // Append
                //
                #if tracker_debug_save
                trace('Save $key (append ${changeset.data.length})');//: ' + changeset.data);
                #end

                (function(data:String, key:String) {
                    backend.runInBackground(function() {

                        // We use and update multiple files to ensure that, in case of crash or any other issue
                        // when writing a file, it will fall back to the other one safely. If anything goes
                        // wrong, there should always be a save file to fall back on.

                        // Encode data
                        var encodedData = Utils.encodeChangesetData(data);
                        
                        // Append first file
                        backend.appendString(saveDataKey1, encodedData);
                        // Mark this first file as the valid one on first id key
                        backend.saveString(saveIdKey1, '1');
                        // Mark this first file as the valid one on second id key
                        backend.saveString(saveIdKey2, '1');

                        // Append second file
                        backend.appendString(saveDataKey2, encodedData);
                        // Mark this second file as the valid one on first id key
                        backend.saveString(saveIdKey1, '2');
                        // Mark this second file as the valid one on second id key
                        backend.saveString(saveIdKey2, '2');

                        backend.runInMain(function() {
                            // Pop busy key
                            var busyIndex = busyKeys.indexOf(key);
                            if (busyIndex != -1) {
                                busyKeys.splice(busyIndex, 1);
                            }
                            else {
                                backend.error('Failed to remove busy key: $key (none in list)');
                            }
                        });

                    });
                })(changeset.data, key);

            } else {

                // Compact
                //
                #if tracker_debug_save
                trace('Save $key (full ${changeset.data.length})');//: ' + changeset.data);
                #end
                
                (function(data:String, key:String) {
                    backend.runInBackground(function() {

                        // We use and update multiple files to ensure that, in case of crash or any other issue
                        // when writing a file, it will fall back to the other one safely. If anything goes
                        // wrong, there should always be a save file to fall back on.

                        // Encode data
                        var encodedData = Utils.encodeChangesetData(data);

                        // Save first file
                        backend.saveString(saveDataKey1, encodedData);
                        // Mark this first file as the valid one on first id key
                        backend.saveString(saveIdKey1, '1');
                        // Mark this first file as the valid one on second id key
                        backend.saveString(saveIdKey2, '1');

                        // Save second file
                        backend.saveString(saveDataKey2, encodedData);
                        // Mark this second file as the valid one on first id key
                        backend.saveString(saveIdKey1, '2');
                        // Mark this second file as the valid one on second id key
                        backend.saveString(saveIdKey2, '2');

                        #if sys
                        // On sys targets, make an additional backup on a plain text file
                        var storageDir = backend.storageDirectory();
                        if (storageDir != null) {
                            try {
                                // Ensure directory exists
                                if (!sys.FileSystem.exists(storageDir)) {
                                    sys.FileSystem.createDirectory(storageDir);
                                }
    
                                // Create hashed data
                                var backupData = encodeHashedString(encodedData);
    
                                // Save backup 1
                                var dataPath = backend.pathJoin([storageDir, backupKey1]);
                                sys.io.File.saveContent(dataPath, backupData);
    
                                // Save backup 2
                                dataPath = backend.pathJoin([storageDir, backupKey2]);
                                sys.io.File.saveContent(dataPath, backupData);
                            }
                            catch (e:Dynamic) {
                                backend.error('Error when saving backup: $e');
                            }
                        }
                        #end

                        backend.runInMain(function() {

                            // Pop busy key
                            var busyIndex = busyKeys.indexOf(key);
                            if (busyIndex != -1) {
                                busyKeys.splice(busyIndex, 1);
                            }
                            else {
                                backend.error('Failed to remove busy key: $key (none in list)');
                            }
                        });
                        

                    });
                })(changeset.data, key);
            }

        });

        // Assign component
        if (model.serializer != serializer) {
            model.serializer = serializer;

            #if !tracker_ceramic
            @:privateAccess serializer.entity = model;
            @:privateAccess serializer.bindAsComponent();
            model.onDestroy(serializer, _ -> {
                serializer.destroy();
                serializer = null;
            });
            #end
        }

    }

    /** Encode the given string `str` and return the result. */
    public static function encodeHashedString(str:String):String {

        var hash = Md5.encode(str);
        var len = str.length;
        return hash + '' + str;

    }

    /** Decode the given `encoded` string and return the result or null if it failed. */
    public static function decodeHashedString(encoded:String):String {

        var i = 0;
        var len = encoded.length;

        // Check hash
        var str = encoded.substring(32);
        var storedHash = encoded.substring(0, 32);
        var computedHash = Md5.encode(str);

        if (storedHash != computedHash) {
            backend.error('Hash mismatch (stored=$storedHash computed=$computedHash)');
            return null;
        }

        return str;

    }

}
