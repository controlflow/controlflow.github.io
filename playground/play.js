var Foo;
(function (Foo) {
    function run() {
        var canvasElement = document.getElementById('canv');
        canvasElement.width = 400;
        canvasElement.height = 400;
        var context = canvasElement.getContext("2d");
        context.fillStyle = "red";
        context.fillRect(0, 0, 400, 400);
    }
    Foo.run = run;
})(Foo || (Foo = {}));
//# sourceMappingURL=play.js.map