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

    var canScheduleImmediateStep:Bool = true;

    var clearDelayAllowImmediateStep:Void->Void = null;

    /**
     * If provided, number of available steps will be limited to this value,
     * meaning older steps will be removed and not recoverable if reaching the limit.
     * Default is: store as many steps as possible, no limit (except available memory?)
     */
    public var maxSteps:Int = -1;

    public function new() {

        super();

    }

    /**
     * Manually clear previous steps outside the given limit
     * @param maxSteps 
     */
    public function clearPreviousStepsOutsideLimit(maxSteps:Int) {

        if (maxSteps > 0) {
            while (currentStep > maxSteps) {
                steps.shift();
                currentStep--;
            }
        }

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

            recordStepIfNeeded();

        });

    }

    function recordStepIfNeeded() {

        // Record one step if pending
        if (stepPending && ignoreSteps <= 0) {
            stepPending = false;
            
            if (currentData != null) {
                while (steps.length - 1 > currentStep) {
                    steps.pop();
                }
                steps.push(currentData.toString());
            }
            else {
                backend.warning('Invalid state: currentData is null when trying to add step!');
                return;
            }

            if (maxSteps > 0) {
                while (steps.length > maxSteps) {
                    steps.shift();
                }
            }

            currentStep = steps.length - 1;

            if (clearDelayAllowImmediateStep != null) {
                clearDelayAllowImmediateStep();
                clearDelayAllowImmediateStep = backend.delay(this, 0.5, () -> {
                    canScheduleImmediateStep = true;
                    clearDelayAllowImmediateStep = null;
                });
            }
        }

    }

    /**
     * Record a step in the undo stack
     */
    public function step():Void {

        if (stepPending || ignoreSteps > 0) {
            return;
        }

        stepPending = true;
        backend.delay(this, 0.05, () -> {
            entity.serializer.synchronize();
            recordStepIfNeeded();
        });

    }

    public function disable():Void {

        ignoreSteps++;

    }

    public function enable():Void {

        ignoreSteps--;

    }

    /**
     * Undo last step, if any
     */
    public function undo():Void {

        if (stepPending) {
            return;
        }

        if (currentStep > 0) {
            currentStep--;

            applyCurrentStep();
        }

    }

    /**
     * Redo last undone step, if any
     */
    public function redo():Void {

        if (stepPending) {
            return;
        }

        if (currentStep < steps.length - 1) {
            currentStep++;

            applyCurrentStep();
        }

    }

    function applyCurrentStep() {

        ignoreSteps++;

        SerializeModel.loadFromData(entity, steps[currentStep], true);
        entity.serializer.compact();

        backend.delay(this, 0.1, () -> {
            ignoreSteps--;
        });

    }

}
