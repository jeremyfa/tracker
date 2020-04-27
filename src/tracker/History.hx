package tracker;

import tracker.Tracker.backend;

class History extends #if tracker_ceramic ceramic.Entity #else Entity #end implements #if tracker_ceramic ceramic.Component #else Component #end {

    var entity:Model;

    var stepPending:Bool;

    var currentData:StringBuf = null;

    var steps:Array<String> = [];

    var currentStep:Int = -1;

    var scheduledStep:Void->Void = null;

    var ignoreSteps:Int = 0;

    public function new() {

        super();

    }

    public function bindAsComponent() {

        var checkInterval = 1.0;
        var compactInterval = 60.0;

        var serializer = entity.serializer;
        if (serializer == null) {
            serializer = new SerializeModel();
            serializer.checkInterval = checkInterval;
            serializer.compactInterval = compactInterval;
        }

        bindSerializer(serializer);

        if (serializer != entity.serializer) {
            entity.serializer = serializer;
        }

        stepPending = true;
        serializer.compact();

    }

    function bindSerializer(serializer:SerializeModel) {

        // Start listening for changes
        serializer.onChangeset(entity, function(changeset) {

            // Keep data up to date
            if (changeset.append) {
                if (currentData != null) {
                    currentData.add(Utils.encodeChangesetData(changeset.data));
                }
                else {
                    backend.warning('Invalid state: currentData is null when trying to append changeset!');
                }
            }
            else {
                currentData = new StringBuf();
                currentData.add(Utils.encodeChangesetData(changeset.data));
            }

            // Record one step if pending
            if (stepPending) {
                stepPending = false;
                
                if (currentData != null) {
                    while (steps.length - 1 > currentStep) {
                        steps.pop();
                    }
                    steps.push(currentData.toString());
                }
                else {
                    backend.warning('Invalid state: currentData is null when trying to add step!');
                }

                currentStep = steps.length - 1;
            }

        });

    }

    public function scheduleStep():Void {

        if (stepPending || ignoreSteps > 0)
            return;

        if (scheduledStep != null)
            scheduledStep();

        scheduledStep = backend.delay(this, 0.5, () -> {
            scheduledStep = null;
            step();
        });

    }

    /**
     * Record a step in the undo stack
     */
    public function step():Void {

        if (stepPending || ignoreSteps > 0)
            return;

        stepPending = true;
        backend.delay(this, 0.1, () -> {
            if (stepPending)
                entity.serializer.synchronize();
        });

    }

    /**
     * Undo last step, if any
     */
    public function undo():Void {

        if (currentStep > 0) {
            currentStep--;

            applyCurrentStep();
        }

    }

    /**
     * Redo last undone step, if any
     */
    public function redo():Void {

        if (currentStep < steps.length - 1) {
            currentStep++;

            applyCurrentStep();
        }

    }

    function applyCurrentStep() {

        ignoreSteps++;

        SerializeModel.loadFromData(entity, steps[currentStep], true);

        backend.delay(this, 0.1, () -> {
            ignoreSteps--;
        });

    }

}
