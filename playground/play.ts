
module Foo {
  export function run() {
    let canvasElement = <HTMLCanvasElement> document.getElementById('canv');
    canvasElement.width = 400;
    canvasElement.height = 400;

    let context = canvasElement.getContext("2d");
    context.fillStyle = "red";
    context.fillRect(0, 0, 400, 400);
  }
}