---
layout: post
title: "JavaScript simple memoization"
date: 2011-03-30 18:53:00
categories: 4210112018
tags: js javascript jscript memoize
---
Последнее время меня увлекает изучать тонкие моменты ECMAScript по такому офигенному сборнику нюансов, как [javascript garden](http://bonsaiden.github.com/JavaScript-Garden/). Пока я ковыряю язык, рождаются собственные js-велосипеды, которые мне грустно выбрасывать, поэтому возникло желание их тут выкладывать.

Одним из первых велосипедов была мемоизация произвольных функций с “каррированными” (отдельными для каждого из аргументов) кэшами:

{% highlight JS %}
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
{% endhighlight %}

Не смотря на некоторые грабли, возникшие при написании, гибкость и лаконичность языка всё же поражает. Проверим мемоизацию на любимом всеми факториале:

{% highlight JS %}
var Math = {
    fact: function(n) {
        console.log('fact('+n+')');
        if (n === 0) return 1;
        return n * Math.fact(n - 1);
    }
}
{% endhighlight %}

Использование (можно и не подменять исходную функцию):

{% highlight JS %}
Math.fact = ControlFlow.memoize(Math.fact);
{% endhighlight %}

Теперь вызовем разок:

```
Math.fact(4)
fact(4)
fact(3)
fact(2)
fact(1)
fact(0)
24
```
А теперь ещё раз:

```
Math.fact(6)
fact(6)
fact(5)
720
```
То есть для вычисления факториала `6` потребовалось только два рекурсивных вызова, так как значение `fact(4)` находится в кеше и не вычисляется заново. Аналогично поддерживаются функции произвольного количества аргументов:

{% highlight JS %}
var Math = {
    sum: ControlFlow.memoize(function() {

        // страшное преобразование arguments
        // в массив для последующего превращения в строку:
        console.log('sum(' +
            Array.prototype.slice.call(arguments).toString() + ')');

        var sum = 0;
        for (var i = 0; i < arguments.length; i++)
            sum += arguments[i];
        return sum;
    })
}
{% endhighlight %}

Usage:

```
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

```
Единственным нюансом является то, что при поиске по кэшу не учитывается параметр `this` функции. То есть функции всех экземпляров будут разделять один и тот же кэш. Дело в том, что обычно мемоизации подвергаются *чистые* функции, не замыкающиеся на какой-либо внешний (и в javascript всегда потенциально изменяемый) контекст. Это достаточно легко поправить и я оставлю реализацию на совести читателя.

p.s. Если я допускаю какие-либо распространнённые ошибки, то буду очень рад комментариям, ничего серъёзного на js не доводилось писать.