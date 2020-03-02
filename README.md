# Tracker

A set of tools to manage events, observable and serializable properties, autorunable functions and data models in general.

This framework has been tested on real use cases when it was embedded in [ceramic engine](https://github.com/ceramic-engine/ceramic).

This is an effort to have an independant haxe library that can also be used outside ceramic, because it can!

```haxe
class Main {
    static function main() {
        new Context();
    }
}

class Context extends tracker.Entity {
    public function new() {
        super();
        
        // Will print 'My name is Jeremy';
        var person = new Person();

        // Will print 'My name is John';
        person.name = 'John';

        // Explicitly listen to name 'change' event
        // (we provide `this` to bind this event handling to `Context`)
        person.onNameChange(this, (newName, prevName) -> {
            trace('Name changed from $prevName to $newName');
        });

        // Change name again
        // Will print 'Name changed from John to James'
        // Will print 'My name is James'
        person.name = 'James';
    }
}

class Person extends tracker.Model {

    @observe public var name:String = 'Jeremy';

    public function new() {
        super();

        autorun(() -> {
            // This will be executed everytime name property is modified
            trace('My name is $name');
        });

    }
}
```

More info on usage and setup soon!