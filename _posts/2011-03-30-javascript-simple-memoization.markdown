---
layout: post
title: "JavaScript function memoization"
date: 2011-03-30 18:53:00
author: Aleksandr Shvedov
tags: js javascript jscript memoize
---
Lately I have been exploring the finer points of ECMAScript with the help of [JavaScript Garden](https://shamansir.github.io/JavaScript-Garden/). Along the way, I have been writing small JavaScript experiments that seem worth sharing here.

One of the first was a memoization helper for functions with any number of arguments. It uses nested, “curried” caches, with a separate level for each argument:

```js
var ControlFlow = {
  memoize: function(func) {
    if (typeof func !== 'function')
      throw "ArgumentError: function expected";

    var cacheRoot = {};
    var resultKey = {};

    return function() {
      var bag = cacheRoot;
      for (var i = 0; i < arguments.length; i++)
        if (arguments[i] in bag)
             bag = bag[arguments[i]];
        else bag = bag[arguments[i]] = {};
      return resultKey in bag
        ? bag[resultKey]
        : bag[resultKey] = func.apply(this, arguments);
    };
  }
}
```

Despite a few pitfalls along the way, I find the language's flexibility and conciseness impressive. Let's try memoizing the familiar factorial function:

```js
var Math = {
  fact: function(n) {
    console.log('fact('+n+')');
    if (n === 0) return 1;
    return n * Math.fact(n - 1);
  }
}
```

We can use it like this (replacing the original function is optional):

```js
Math.fact = ControlFlow.memoize(Math.fact);
```

First, call it once:

    Math.fact(4)
    fact(4)
    fact(3)
    fact(2)
    fact(1)
    fact(0)
    24

Then call it again with a larger argument:

    Math.fact(6)
    fact(6)
    fact(5)
    720

Only `fact(6)` and `fact(5)` need to be computed: `fact(4)` is already cached. Functions with a variable number of arguments work in the same way:

```js
var Math = {
  sum: ControlFlow.memoize(function() {
    // convert arguments to an array
    // so it can be formatted as a string
    console.log('sum(' +
      Array.prototype.slice.call(arguments).toString() + ')');

    var sum = 0;
    for (var i = 0; i < arguments.length; i++)
      sum += arguments[i];
    return sum;
  })
}
```

Usage:

    Math.sum(2, 2)
    sum(2,2)
    4
    
    Math.sum(2, 2)
    4
    
    Math.sum(1, 2, 3)
    sum(1,2,3)
    6
    
    Math.sum(1, 2, 3)
    6

One limitation is that the cache lookup does not take the function's `this` value into account. Calls to the same memoized function on different objects therefore share a cache. Memoization is normally used with *pure* functions, whose results do not depend on external state (which can always be mutable in JavaScript). Including `this` in the cache key is a straightforward extension, which I will leave to the reader.