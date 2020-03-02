package tracker.test;

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
