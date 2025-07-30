# Tracker

A powerful reactive programming framework for Haxe that provides observable properties, event management, autorun functions, and data models with built-in serialization support.

## Features

- 🔄 **Reactive Properties** - Automatically track changes with `@observe`
- 🎯 **Events System** - Type-safe event handling with `@event`
- ⚡ **Autorun Functions** - Functions that automatically re-execute when dependencies change
- 💾 **Serialization** - Built-in model serialization with `@serialize`
- 🧮 **Computed Properties** - Derived values that update automatically with `@compute`
- 🏗️ **Memory Safe** - Automatic cleanup when entities are destroyed

## Installation

Install with haxelib:

```bash
haxelib install tracker
```

```hxml
# Add to your .hxml file
-lib tracker
```

## Quick Start

```haxe
import tracker.Model;

class Main {
    static function main() {
        var app = new TodoApp();
        app.addTodo("Learn Tracker");
        app.todos[0].completed = true; // Automatically triggers updates!
    }
}

class TodoApp extends Model {
    @observe public var todos:Array<Todo> = [];

    @compute public function completedCount():Int {
        var count = 0;
        for (todo in todos) {
            if (todo.completed) count++;
        }
        return count;
    }

    @compute public function pendingCount():Int {
        return todos.length - completedCount;
    }

    public function new() {
        super();

        // Automatically runs whenever todos or computed values change
        autorun(() -> {
            trace('Todos: ${todos.length} total, $completedCount completed, $pendingCount pending');
        });
    }

    public function addTodo(text:String):Void {
        var todo = new Todo(text);
        var newTodos = [].concat(todos);
        newTodos.push(todo);
        todos = newTodos; // Trigger array change
    }
}

class Todo extends Model {
    @observe public var text:String;
    @observe public var completed:Bool = false;

    public function new(text:String) {
        super();
        this.text = text;
    }
}
```

## Core Concepts

### Model - Your Main Building Block

`tracker.Model` is the primary class you'll extend. It combines observable properties, events, and serialization:

```haxe
class User extends tracker.Model {
    @observe public var name:String;
    @observe public var email:String;
    @observe public var age:Int = 0;

    @compute public function displayName():String {
        return name != null ? name : "Anonymous";
    }

    @event function login(success:Bool);
}
```

`tracker.Model` is also an `Entity`.

### Observable Properties

Properties marked with `@observe` automatically track changes and generate event methods:

```haxe
class Counter extends Model {
    @observe public var count:Int = 0;

    // You can also define custom getters/setters
    @observe public var doubled(get,set):Int;
    var _doubled:Int = 0;

    function get_doubled():Int {
        return _doubled;
    }

    function set_doubled(value:Int):Int {
        // Custom logic here
        _doubled = value * 2;
        return _doubled;
    }
}

// Usage - methods are automatically generated:
var counter = new Counter();
counter.onCountChange(this, (newValue, oldValue) -> {
    trace('Count changed from $oldValue to $newValue');
});
counter.count = 5; // Triggers the change event
```

**Important notes:**
- Arrays and maps don't trigger changes when modified in place. You must create a new instance:
  ```haxe
  // Won't trigger change:
  myModel.items.push(newItem);
  myModel.items = myModel.items; // Still the same reference!

  // Will trigger change (arrays):
  var newItems = [].concat(myModel.items);
  newItems.push(newItem);
  myModel.items = newItems;

  // Will trigger change (maps):
  var newMap = new Map<String, Item>();
  for (key => value in myModel.itemMap) {
      newMap.set(key, value);
  }
  newMap.set("newKey", newItem);
  myModel.itemMap = newMap;
  ```

### Autorun - Reactive Functions

Autorun functions automatically re-execute when any observable property they access changes:

```haxe
class ReactiveExample extends Model {
    @observe public var firstName:String = "John";
    @observe public var lastName:String = "Doe";

    public function new() {
        super();

        // This will re-run whenever firstName or lastName changes
        autorun(() -> {
            trace('Full name: $firstName $lastName');
        });
    }
}
```

### Events System

Define type-safe events with `@event` for actions and notifications:

```haxe
class MediaPlayer extends Model {
    @observe public var currentTime:Float = 0;
    @observe public var duration:Float = 0;

    @event public function playbackEvent(type:String, position:Float);
    @event public function error(code:Int, message:String);

    public function play():Void {
        emitPlaybackEvent("start", currentTime);
        // Start playback logic
    }

    public function checkProgress():Void {
        var progress = currentTime / duration;
        if (progress >= 0.25 && !firstQuartileReached) {
            firstQuartileReached = true;
            emitPlaybackEvent("firstQuartile", currentTime);
        }
    }
}

// Usage - listen to events:
var player = new MediaPlayer();
player.onPlaybackEvent(this, (type, position) -> {
    trace('Playback event: $type at position $position');
});
player.onError(this, (code, message) -> {
    trace('Player error $code: $message');
});
```

### Computed Properties

Create derived values that automatically update:

```haxe
class ShoppingCart extends Model {
    @observe public var items:Array<Item> = [];
    @observe public var taxRate:Float = 0.08;

    @compute public function subtotal():Float {
        var total = 0.0;
        for (item in items) {
            total += item.price * item.quantity;
        }
        return total;
    }

    @compute public function tax():Float {
        return subtotal * taxRate;
    }

    @compute public function total():Float {
        return subtotal + tax;
    }
}
```

## Detailed API Reference

### Observable Properties

When you mark a property with `@observe`, Tracker generates:

- **Getter/Setter** - Automatically tracks dependencies and emits changes
- **Change Events** - `onPropertyChange()`, `oncePropertyChange()`, `offPropertyChange()`
- **Invalidation** - `invalidateProperty()` to force updates

```haxe
class Example extends Model {
    @observe public var status:String = "idle";
}

// Generated methods:
example.onStatusChange(owner, (newVal, oldVal) -> { });
example.onceStatusChange(owner, (newVal, oldVal) -> { });
example.offStatusChange(callback);
example.invalidateStatus();
```

### Event Methods

For each `@event` declaration, Tracker generates:

```haxe
class Example extends Model {
    @event function update(data:String, timestamp:Float);
}

// Generated methods:
example.onUpdate(owner, (data, timestamp) -> { });
example.onceUpdate(owner, (data, timestamp) -> { });
example.offUpdate(?callback);
example.emitUpdate(data, timestamp);
example.listensUpdate(); // Returns true if has listeners
```

### Autorun Control

```haxe
// Import for cleaner code
import tracker.Autorun.unobserve;
import tracker.Autorun.unobserved;
import tracker.Autorun.reobserve;

// Create an autorun from within an `Entity`
var myAutorun = autorun(() -> {
    // Read observable values that should trigger re-runs
    var currentValue = model.value;
    var currentStatus = model.status;

    // Use unobserve/reobserve to control dependencies
    unobserve();

    // Perform side effects without creating dependencies
    if (currentStatus == READY) {
        performExpensiveOperation(currentValue);
    }

    // Selectively observe only what matters
    reobserve();
    var threshold = model.threshold;
    unobserve();

    // Another way to run code without creating dependencies
    unobserved(() -> {
        // Access to observables here won't create dependencies
        var value = model.someProperty;
    });

    if (currentValue > threshold) {
        sendNotification();
    }
});

// An autorun can also be created as a standalone one
var myAutorun = new Autorun(() -> {
    // ...
});

// Destroy autorun when not needed anymore.
// (if autorun() was called within an `Entity` class, it will
// be automatically destroyed when the entity is destroyed too)
myAutorun.destroy();
```

### Advanced Autorun Features

#### @autorun Metadata

Mark methods to run automatically when their dependencies change:

```haxe
class VideoPlayer extends Model {
    @observe public var volume:Float = 1.0;
    @observe public var muted:Bool = false;

    @autorun function updateAudioState():Void {
        var effectiveVolume = muted ? 0 : volume;
        // This method re-runs whenever muted or volume changes
        audioEngine.setVolume(effectiveVolume);
    }
}
```

Using `@autorun function someFunc()` metadata is the equivalent of adding `autorun(someFunc);` at the end of the entity's constructor.

#### until() - Wait for Conditions

Execute code once when a condition expression becomes true:

```haxe
import tracker.Until.until;

class DataLoader extends Model {
    @observe public var data:Array<Item> = null;
    @observe public var loaded:Bool = false;

    public function new() {
        super();

        // Wait until data is loaded
        until(loaded == true, () -> {
            trace('Data loaded with ${data.length} items');
        });

        // With timeout
        until(loaded == true,
            () -> trace('Loaded!'),
            5.0, // timeout in seconds
            () -> trace('Timeout!')
        );
    }
}
```

#### cease() - Stop and Destroy Current Autorun

Permanently stop and destroy an autorun from within its execution:

```haxe
import tracker.Autorun.cease;

class ResourceLoader extends Model {
    @observe public var progress:Float = 0;

    public function trackProgress():Void {
        autorun(() -> {
            trace('Progress: $progress%');
            if (progress >= 100) {
                trace('Complete!');
                cease(); // Stops and destroys this autorun - it will never run again
            }
        });
    }
}
```

`cease()` completely destroys the current autorun. It won't run again even if dependencies change. Use it for one-time conditions or cleanup.

#### unobserve/reobserve - Fine Control

Control dependency tracking for performance and logic:

```haxe
class DataProcessor extends Model {
    @observe public var config:Config;
    @observe public var data:Data;

    @autorun function processChanges():Void {
        // Read values that should trigger re-runs
        var currentConfig = config;
        var currentData = data;

        // Stop observing for side effects
        unobserve();

        // Perform operations without creating dependencies
        if (currentConfig.enabled) {
            updateUI(currentData);

            // Selectively observe specific properties
            reobserve();
            var threshold = currentConfig.threshold;
            unobserve();

            if (currentData.value > threshold) {
                sendNotification();
            }
        }
    }
}
```

#### Separate implicit bindings from side effects

If you want to strictly separate observed fields bindings from side effects, you can provide two different callbacks when using `autorun()`:

```haxe
autorun(() -> {
    // Create an implicit binding
    var observedBinding = this.someObservedField;
},
() -> {
    // Perform some side effect
    updateUI();
});
```

This is, however, not very flexible, because it doesn't give you access to `observedBinding` variable from the second callback, and it feels like `observedBinding` local variable isn't even used, so the preferred solution is generally using `unobserve()` and `reobserve()` or `unobserved(() -> { ... })`, which give you access to the observed scope values from the unobserved one naturally.

### Model Features

```haxe
class Product extends Model {
    @observe public var name:String;
    @observe public var price:Float;
    @serialize public var sku:String; // Include in serialization

    // Lifecycle hooks
    override function destroy():Void {
        // Cleanup code here
        super.destroy();
    }
}

// Check if any observable property has changed
if (product.observedDirty) {
    // Something changed in the model
}

// Entity properties
product.destroyed; // Check if destroyed
product.id = "product-123"; // Optional identifier
```

## Advanced Topics

### Automatic Memory Management with @owner

The `@owner` metadata specifies that the fields marked with it are owned by the object. When the object is eventually destroyed, all its fields marked with `@owner` will be automatically destroyed as well.

```haxe
class GameScreen extends Model {
    // Single entity - automatically destroyed
    @owner var player:Player;

    // Arrays of entities - each item is destroyed
    @owner var enemies:Array<Enemy> = [];

    // String maps - all values are destroyed
    @owner var powerups:Map<String, Powerup> = new Map();

    // Can be combined with @observe
    @owner @observe public var ui:UIManager;

    public function new() {
        super();

        // Create owned entities - no manual cleanup needed!
        player = new Player();

        // For arrays, create new instance to trigger change
        var newEnemies = [].concat(enemies);
        newEnemies.push(new Enemy());
        enemies = newEnemies;

        // For maps, create new instance to trigger change
        var newPowerups = new Map<String, Powerup>();
        for (key => value in powerups) {
            newPowerups.set(key, value);
        }
        newPowerups.set("speed", new SpeedBoost());
        powerups = newPowerups;

        ui = new UIManager();
    }

    // No need to override destroy() - children are cleaned up automatically!
}

// Without @owner, you'd need to do this manually:
class ManualCleanupScreen extends Model {
    var player:Player;

    override function destroy():Void {
        if (player != null) {
            player.destroy();
            player = null;
        }
        super.destroy();
    }
}
```

### Serialization

Models can be serialized/deserialized with the `@serialize` metadata:

```haxe
class Settings extends Model {
    @serialize public var theme:String = "dark";      // Implicitly @observe
    @serialize public var fontSize:Int = 14;          // Implicitly @observe
    @observe public var tempValue:String;             // Not serialized

    public function save():String {
        return tracker.Serialize.serialize(this);
    }

    public function load(data:String):Void {
        tracker.Serialize.deserialize(this, data);
    }
}
```

**Note:** Fields marked with `@serialize` are automatically observable - you don't need to add `@observe` to them.

### Incremental saves and loading

Tracker has a built-in system to auto-save a large model hierarchy with `tracker.SaveModel` extension.

It can automatically detect which model objects have changed and saved data to disk of those object without needing to re-serialize the entire hierarchy of object, making it viable for continuous saves in realtime without freezing the app.

```haxe
using tracker.SaveModel;

class MyGameModel extends Model {
    @serialize public var players:Array<Player> = [];
    @serialize public var achievements:Array<Achievement> = [];
    @serialize public var currentLevel:Int = 1;

    public function new() {
        super();

        this.loadFromKey('my-game');    // Load saved data when initializing my model, if any
        this.autoSaveAsKey('my-game');  // Auto-save my data when it changes, synced every second
    }
}
```

```haxe
// Alternatively, you can specify different check intervals

// The interval between each incremental save. Each append is adding
// changeset data to the existing save file.
// (only saves when data has changed)
final appendInterval = 5.0;

// The interval between "compacting": re-serializes the entire hierarchy of objects to
// create a compacted save that prevents the save file from growing indefinitely
final compactInterval = 300.0;
this.autoSaveAsKey('my-game', appendInterval, compactInterval);
```

### Memory Management

Entities (including Models) should be destroyed when no longer needed:

```haxe
class MyApp extends Model {
    var buttons:Array<Button> = [];

    public function cleanup():Void {
        // Destroy all child entities
        for (button in buttons) {
            button.destroy();
        }
        buttons = [];

        // Destroy self
        destroy();
    }
}
```

When you bind events or create autoruns with an owner, they're automatically cleaned up when the owner is destroyed:

```haxe
class View extends Model {
    public function new(model:DataModel) {
        super();

        // These are automatically cleaned up when 'this' is destroyed
        model.onDataChange(this, handleDataChange);
        autorun(updateView);
    }
}
```

### Performance Considerations

1. **Batch Updates** - Group multiple property changes together
2. **Unobserve Complex Operations** - Use `Autorun.unobserved()` for bulk operations
3. **Destroy Unused Entities** - Prevent memory leaks by destroying entities
4. **Computed Caching** - Computed properties cache their results automatically

```haxe
// Batch updates example
Autorun.unobserved(() -> {
    // Multiple changes won't trigger individual updates
    model.x = 100;
    model.y = 200;
    model.width = 300;
    model.height = 400;
});
// Autorun will execute once after all changes
```

## Examples

### Form Validation

```haxe
class LoginForm extends Model {
    @observe public var username:String = "";
    @observe public var password:String = "";

    @compute public function isUsernameValid():Bool {
        return username.length >= 3;
    }

    @compute public function isPasswordValid():Bool {
        return password.length >= 8;
    }

    @compute public function canSubmit():Bool {
        return isUsernameValid && isPasswordValid;
    }

    @event function submit(success:Bool);

    public function new() {
        super();

        autorun(() -> {
            trace('Form is ${canSubmit ? "valid" : "invalid"}');
        });
    }
}
```

### Reactive List

```haxe
class TaskList extends Model {
    @observe public var tasks:Array<Task> = [];
    @observe public var filter:String = "all"; // all, active, completed

    @compute public function visibleTasks():Array<Task> {
        return switch filter {
            case "active": tasks.filter(t -> !t.completed);
            case "completed": tasks.filter(t -> t.completed);
            default: tasks;
        }
    }

    public function addTask(text:String):Task {
        var task = new Task(text);
        var newTasks = [].concat(tasks);
        newTasks.push(task);
        tasks = newTasks; // Trigger array change
        return task;
    }
}

class Task extends Model {
    @observe public var text:String;
    @observe public var completed:Bool = false;

    public function new(text:String) {
        super();
        this.text = text;
    }
}
```

### State Machine

```haxe
class FileDownloader extends Model {
    @observe public var state:DownloadState = Idle;
    @observe public var progress:Float = 0;
    @observe public var bytesLoaded:Int = 0;

    @event public function complete(filePath:String, fileSize:Int);
    @event public function failed(error:String, retryable:Bool);

    public function new() {
        super();

        // React to state changes using the auto-generated method
        onStateChange(this, (newState, oldState) -> {
            trace('Download state: $oldState -> $newState');
        });
    }

    public function startDownload(url:String):Void {
        if (state == Idle) {
            state = Downloading;
            // Download logic here...
        }
    }

    function onDownloadComplete(path:String, size:Int):Void {
        state = Completed;
        emitComplete(path, size);
    }

    function onDownloadError(err:String):Void {
        state = Failed;
        emitFailed(err, canRetry(err));
    }
}

enum DownloadState {
    Idle;
    Downloading;
    Paused;
    Completed;
    Failed;
}
```

## Best Practices

### When to Use Autorun vs Events

**Use Autorun when:**
- You want to keep something in sync automatically
- The relationship between data and side effects is clear
- You're updating UI based on model changes

**Use Events when:**
- You need explicit control over when actions occur
- Multiple independent systems need to react
- You're integrating with external APIs

### Entity Lifecycle

1. **Always provide an owner** when binding events
2. **Destroy entities** when they're no longer needed
3. **Use parent-child relationships** to manage cleanup

```haxe
class Screen extends Model {
    var components:Array<Component> = [];

    public function addComponent(component:Component):Void {
        components.push(component);
        // Bind with this screen as owner
        component.onUpdate(this, handleComponentUpdate);
    }

    override function destroy():Void {
        // Destroy all children first
        for (component in components) {
            component.destroy();
        }
        components = [];
        super.destroy();
    }
}
```

## Configuration

### Build Flags

```hxml
# Use custom backend implementation
-D tracker_custom_backend

# Use manual immediate callback flushing (power user feature for fined grained control)
-D tracker_manual_flush
```

### Custom Backend

Implement the `tracker.Backend` interface to customize platform-specific behavior:

```haxe
class MyBackend implements tracker.Backend {
    public function new() {}

    public function onceImmediate(handler:Void->Void):Void {
        // Implementation
    }

    // ... implement other required methods
}

// Set custom backend
Tracker.backend = new MyBackend();
```

## Migration Tips

If you're coming from other reactive frameworks in JS land:

- **MobX users**: `@observable` → `@observe`, `computed` → `@compute`, `reaction` → `autorun`
- **Vue users**: `data` → `@observe` properties, `computed` → `@compute`, `watch` → `autorun`
- **Knockout users**: `observable()` → `@observe`, `computed()` → `@compute`
