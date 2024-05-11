package tracker;

@:structInit
class ShareChangeset {

    public var items:Array<ShareItem>;

    public function new(items:Array<ShareItem>) {

        this.items = items;

    }

    function toString() {

        var toPrint = [];
        for (item in items) {
            toPrint.push(item);
        }
        return '' + {
            items: toPrint
        };

    }

}