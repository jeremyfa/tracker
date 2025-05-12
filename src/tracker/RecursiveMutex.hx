package tracker;

#if sys
import sys.thread.Mutex;
import sys.thread.Thread;
#end

/**
 * RecursiveMutex - A reentrant mutex implementation that allows
 * the same thread to acquire the lock multiple times.
 */
class RecursiveMutex {

    #if sys
    /**
     * The underlying mutex
     */
    private var mutex:Mutex;

    /**
     * Track the current owner thread
     */
    private var ownerThread:Thread;

    /**
     * Count how many times the owner thread has acquired the lock
     */
    private var lockCount:Int;
    #end

    /**
     * Create a new recursive mutex
     */
    public function new() {
        #if sys
        mutex = new Mutex();
        lockCount = 0;
        ownerThread = null;
        #end
    }

    /**
     * Acquire the mutex lock
     * If the current thread already owns the lock,
     * increment the lock count instead of blocking
     */
    public function acquire():Void {
        #if sys
        var currentThread = Thread.current();

        // Fast path: check if we already own the lock
        if (currentThread == ownerThread) {
            // We already own the lock, just increment the counter
            lockCount++;
            return;
        }

        // Slow path: we don't own the lock, so acquire it
        mutex.acquire();

        // Now we own the lock
        ownerThread = currentThread;
        lockCount = 1;
        #end
    }

    /**
     * Release the mutex lock
     * Only actually releases the lock when the lock count reaches zero
     * @throws String if the current thread is not the owner
     */
    public function release():Void {
        #if sys
        var currentThread = Thread.current();

        // Ensure this thread owns the lock
        if (currentThread != ownerThread) {
            throw "RecursiveMutex.release: current thread does not own the mutex";
        }

        // Decrement the lock count
        lockCount--;

        // If lock count is zero, actually release the mutex
        if (lockCount == 0) {
            ownerThread = null;
            mutex.release();
        }
        #end
    }

    /**
     * Try to acquire the mutex without blocking
     * @return Bool true if the mutex was acquired, false otherwise
     */
    public function tryAcquire():Bool {
        #if sys
        var currentThread = Thread.current();

        // Fast path: check if we already own the lock
        if (currentThread == ownerThread) {
            // We already own the lock, just increment the counter
            lockCount++;
            return true;
        }

        // Try to acquire the lock
        if (mutex.tryAcquire()) {
            // We got the lock
            ownerThread = currentThread;
            lockCount = 1;
            return true;
        }

        // Failed to acquire the lock
        return false;
        #else
        return false;
        #end
    }

    /**
     * Get the current lock count (for debugging)
     * @return Int The number of times the current owner has acquired the lock
     */
    public function getLockCount():Int {
        #if sys
        return lockCount;
        #else
        return 0;
        #end
    }

    /**
     * Check if the current thread owns the mutex
     * @return Bool true if the current thread owns the mutex
     */
    public function isOwnedByCurrentThread():Bool {
        #if sys
        return Thread.current() == ownerThread;
        #else
        return false;
        #end
    }
}
