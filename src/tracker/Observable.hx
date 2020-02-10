package tracker;

/** Observable allows to observe properties of an object. */
#if !macro
@:autoBuild(tracker.macros.ObservableMacro.build())
#end
interface Observable {}
