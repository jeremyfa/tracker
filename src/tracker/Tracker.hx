package tracker;

class Tracker {

    #if (tracker_custom_backend || tracker_no_default_backend)
    public static var backend:Backend;
    #else
    public static var backend:Backend = new DefaultBackend();
    #end

}
