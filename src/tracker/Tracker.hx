package tracker;

class Tracker {

    public static var backend:Backend #if (!tracker_custom_backend && !tracker_no_default_backend) = new DefaultBackend() #end;

}
