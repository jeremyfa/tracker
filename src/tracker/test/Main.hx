package tracker.test;

class Main {
	
	static function main() {
		
		trace("Hello, world!");

		Tracker.backend = new DefaultBackend();

		var testModel = SaveModel.getSavedOrCreate(TestModel, 'testsave');
		testModel.init();
		
	}

}
