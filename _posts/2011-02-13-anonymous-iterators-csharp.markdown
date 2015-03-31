---
layout: post
title: "Анонимные итераторы в C#?"
date: 2011-02-13 22:00:00
categories: 3276310698
tags: csharp async yield yield return await try finally asyncctp asyncenumerator lambda-expressions
---
Сегодня мы поиграем с новыми фичами C# 5.0 из состава [Async CTP](http://www.microsoft.com/downloads/en/details.aspx?FamilyID=18712f38-fcd2-4e9f-9028-8373dc5732b2&displaylang=en), а конкретно с новыми трансформациями на уровне компилятора для поддержки ключевых слов `async`/`await` (скорее всего в релизе эти ключевые слова будут другими, общественность не радостно встретила такой выбор). [Тут](http://www.microsoft.com/downloads/en/details.aspx?FamilyID=C59F7633-37C7-4364-8F13-EFDB1E5CCB21) лежит спека с подробным описанием нововведений, однако на данный момент компилятор C# не сильно ей следует.

По своей сути фича очень и очень простая, а необходимые для её реализации элементы имеются в компиляторе ещё начиная с версии C# 2.0 - это трансформации, которые компилятор делает для `yield return`-итераторов. Трансформация заключается в разбиение метода-итератора на набор состояний по точкам вызова `yeild return`/`yield break`, а затем компилирование класса, реализующего `IEnumerable<T>` (или `IEnumerator<T>` и не обобщённые версии обоих) с большим `switch` по состояниям исходного метода в реализации `MoveNext()`. Очень хорошо и подробно про имплементацию итераторов в Microsoft’ском компиляторе C# пишет Jon Skeet [здесь](http://csharpindepth.com/Articles/Chapter6/IteratorBlockImplementation.aspx).

Такие крутые дядьки как Jeffrey Richter ещё давным давно придумали использовать эту же трансформацию компилятора для упрощения работы с различными асинхронными операциями. Такие штуки, как `[AsyncEnumerator](http://msdn.microsoft.com/en-us/magazine/cc546608.aspx)`, позволяли представить асинхронный код практически так же, как синхронный, без моря лямбда-выражений и замыканий. К сожалению, данное решение нельзя назвать достаточно симпатичным из-за необходимости общения в блоке итератора со вспомогательными классами.

Сегодня мы решим обратную задачу - сделаем из `async`-методов блоки `yield`-итераторов! А так как в качестве `async`-методов могут выступать лямбда-выражения, то мы можем получить анонимные итераторы в C# (`yield return` в лямбда выражениях [запрещён](http://blogs.msdn.com/b/ericlippert/archive/2009/08/24/iterator-blocks-part-seven-why-no-anonymous-iterators.aspx)):

{% highlight C# %}
Func<string, Task<int>> f = async url =>
{
    var web = new System.Net.WebClient();
    var page = await web.DownloadStringTaskAsync(url);
    Console.WriteLine(page);
};
{% endhighlight %}

Итак, приступим:

{% highlight C# %}
using System;
using System.Collections;
using System.Collections.Generic;
using System.Threading;

public static class Iterator
{
{% endhighlight %}

Определим вложенный класс-awaiter (пользователь вовсе не должен замечать этот класс, он необходим для инфраструктуры C# `async`):

{% highlight C# %}
public abstract class Awaiter<T>
{
    public Awaiter<T> GetAwaiter() { return this; }
    public abstract bool BeginAwait(Action next);
    public abstract void EndAwait();
}
{% endhighlight %}

Согласно спецификации, любое выражение под `await` должно обладать экземплярным методом (или extension-методом) с именем `GetAwaiter`, возвращающее значение типа, в котором определены методы `BeginAwait` и `EndAwait`. Первый из них должен иметь параметр типа `System.Action` и возвращать `bool`-значение, второй - не иметь параметров и возвращать значение любого типа или `void`.

Смысл всего этого добра очень прост - когда вы ожидаете с помощью `await` какое-либо выражение, то у этого выражение вызывается метод `GetAwaiter()` и у возвращённого значения вызывается `BeginAwait`, при этом туда передаётся некий `Action`-делегат. Внутри себя `BeginAwait` как-либо запускает асинхронную операцию, а в качестве callback’а использует переданный `Action`-делегат. Если запуск асинхронной операции произошёл успешно, то `BeginAwait` возвращает `true` и исполнение `async`-метода прерывается (управление возвращается коду, вызвавшему `async`-метод). Позже, когда асинхронная операция завершится, она вызывает в качестве callback’а `Action`-делегат, который на самом деле вызывает продолжение исполнения `async`-метода с момента последнего `await`'а. При этом у последнего awaiter-класса вызывается метод `EndAwait`, который может вернуть результат асинхронной операции (как в примере выше). Помимо всего этого, `BeginAwait` может вернуть `false` и тогда выполнение `async`-метода продолжится синхронно (например, если операция выполнилась очень быстро и не потребовала асинхронности), с последующим вызовом `EndAwait` для получения результата.

В нашей реализации тип значения под `await`-выражением и класс-awaiter являются одним и тем же типом, поэтому `GetAwaiter` просто делает `return this`.

Далее определим тип делегата, возвращающий описанный нами класс-awaiter, им будет удобнее пользоваться в дальнейшем, чем `Func<T, Awaiter<T> >`:

{% highlight C# %}
public delegate Awaiter<T> Yield<T>(T value);
{% endhighlight %}

Главный метод из public surface получает `Action`-делегат (который должен являться `async`-методом) с единственным параметром типа делегата `Yeild<T>`:

{% highlight C# %}
public static IEnumerable<T> Of<T>(Action<Yield<T>> @async)
{
    if (@async == null)
        throw new ArgumentNullException("async");

    return new IteratorAwaiter<T>(@async);
}
{% endhighlight %}

Теперь самое сложное, реализация класса `IteratorAwaiter<T>`:

{% highlight C# %}
sealed class IteratorAwaiter<T>
    : Awaiter<T>, IEnumerator<T>, IEnumerable<T>
{
    readonly Action<Yield<T>> @async;
    readonly int initialThreadId;
    Action moveNext;
    T currentValue;

    public IteratorAwaiter(Action<Yield<T>> @async)
    {
        this.@async = @async;
        this.initialThreadId =
            Thread.CurrentThread.ManagedThreadId;
        this.moveNext = InitialMoveNext;
    }
{% endhighlight %}

Класс сохраняет в поле `Action`-делегат из `async`-метода и идентификатор текущего потока (это нужно для тех же целей, что и в итераторах). При этом поле `moveNext` изначально указывает на метод `InitialMoveNext`, который запускает `async`-метод и в качестве делегата `Yield<T>` передаёт лямбда-выражение, устанавливающее значение полю `currentValue` и возвращающее класс `IteratorAwaiter<T>` инфраструктуре `async` в качестве `Awaiter<T>`:

{% highlight C# %}
void InitialMoveNext()
{
    this.moveNext = null;
    this.@async(value => {
        this.currentValue = value;
        return this;
    });
}
{% endhighlight %}

Данный код решает проблему того, что `async`-методы в C# не являются отложенными - код до первого `await` всегда вызывается *синхронно*, а вот исполнение `yield return`-итераторов всегда отложено до первого вызова `MoveNext`. Поэтому, чтобы из `async`-метода сделать итератор, надо отложить вызов `@async` до первого вызова `MoveNext`.

Теперь реализация `Awaiter<T>`, которая просто сохраняет делегат продолжения в то же поле `moveNext` и обнуляет его при продолжении работы `async`-метода (вызов `EndAwait`):

{% highlight C# %}
public override bool BeginAwait(Action next)
{
    this.moveNext = next;
    return true;
}

public override void EndAwait()
{
    this.moveNext = null;
}
{% endhighlight %}

Реализация `IEnumerator<T>` раскрывает все секреты:

{% highlight C# %}
public T Current
{
    get { return this.currentValue; }
}

object IEnumerator.Current
{
    get { return this.currentValue; }
}

public bool MoveNext()
{
    if (this.moveNext == null) return false;
    this.moveNext();
    return (this.moveNext != null);
}

public void Reset() { }
public void Dispose() { }
{% endhighlight %}

Знаток итераторов тут же заметит некорректную реализацию `Dispose`, однако я пока отложу обсуждение данной проблемы. Интерес представляет метод `MoveNext`, который вызывает делегат из поля `moveNext`, и проверяет это же поле после вызова на `null`. Дело в том, что если в `async`-методе не останется `await`'ов, то последний вызов `EndAwait` установит поле `moveNext` в `null` и итератор должен будет сообщить, что он “закончился”.

Наконец, реализация `IEnumerable<T>`, которая создаёт копию `IteratorAwaiter<T>` если запрашивают ещё один `IEnumerator<T>` из другого потока или когда этот экземпляр уже хоть раз использовали для перебора (именно поэтому `InitialMoveNext` первым делом обнуляет поле `moveNext`) - это необходимо для поддержки оптимизации, при которой `IEnumerable<T>` и `IEnumerator<T>` являются одним и тем же экземпляром, так же как в итераторах C#:

{% highlight C# %}
public IEnumerator<T> GetEnumerator()
{
    if (Thread.CurrentThread.ManagedThreadId
                        != this.initialThreadId
        || this.moveNext == null
        || this.moveNext.Target != this)
    {
        return new IteratorAwaiter<T>(@async);
    }

    return this;
}

IEnumerator IEnumerable.GetEnumerator()
{
    return GetEnumerator();
}
{% endhighlight %}

Вот и всё, полный исходный код доступен [здесь](http://ideone.com/cvNkF). Понимаю, выглядит это всё жестоко, но если есть желание поглубже разобраться со внутренностями Async CTP, то очень советую побегать по данному коду отладчиком.

Теперь мы можем определять итераторы в виде лямбда-выражений и это даже не особо страшно выглядит (к сожалению, необходима явная аннотация типа итератора):

{% highlight C# %}
var xs = Iterator.Of<int>(async yield =>
{
    await yield(100);
    await yield(200);

    for (int i = 0; i < 10; i++)
    {
        await yield(i);

        if (i % 6 == 0)
            return; // вместо yield break
    }
});

foreach (var x in xs) Console.WriteLine(x);
{% endhighlight %}

Обратите внимание, что всё лямбда-выражение приводится к типу делегата `Action<T>`, не имеющему возвращаемого значения, при этом вызов `return` начинает играть роль `yield break`.

Стоит отметить, что делегат `yield`-параметра можно вызвать где угодно по коду, но смысл итератором будут возвращаться только значения, передаваемые под `await`-выражением. Можно было бы предусмотреть буфер и позволить итератору энергично наполнять его последовательными вызовами `yield`, а потом последовательно отдавать буфер при следующем вызове `await`.

По производительности данный итератор лишь в *1.5-2 раза* медленнее обычного `yield return`, из-за дополнительных вызовов через делегаты и некоторого оверхэда на инфраструктуру `async`. К сожелению, требуется сборка *AsyncCtpLibrary.dll* из состава Async CTP, хотя возможно подменить её на свою, реализовав небольшой функционал.

Ещё одно отличие `async`-методов от итераторов - возможность делать `await` внутри `try`-`catch` (это запрещено в итераторах):

{% highlight C# %}
async static void CatchIteratorImpl(Iterator.Yield<string> yield)
{
    try
    {
        await yield("indise try");
        throw new Exception();
    }
    catch   { Console.WriteLine("=> catch"); }
    finally { Console.WriteLine("=> finally"); }
}

static void Main(string[] args)
{
    Iterator
        .Of<string>(CatchIteratorImpl)
        .Materialize()
        .Run(Console.WriteLine);
}
{% endhighlight %}

В примере я использую методы из [Reactive Extensions for .NET](http://msdn.microsoft.com/en-us/devlabs/ee794896) (`Run` - это просто `foreach` с телом из переданного делегата, `Materialize` позволяет увидеть момент завершения последовательности), получаем вывод:

```
OnNext(indise try)
=> catch
=> finally
OnCompleted()
```
Это всё хорошо, а теперь о плохом - данная реализация не может корректно обрабатывать ситуации, когда пользователь итератора сам прекратит перебор и запросит у итератора `Dispose`. Если к данному моменту исполнение итератора C# было внутри `try-finally` (в итераторах C# они разрешены), то будет выполнен `finally`-блок, тогда как в случае наших итераторов из `async`-методов код `finally` выполнен не будет:

{% highlight C# %}
var xs = Iterator.Of<int>(async yield =>
{
    try
    {
        await yield(1);
        await yield(2);
        await yield(3);
    }
    finally { Console.WriteLine("=> finally"); }
});

xs.Take(2) // <== останавливаем перебор итератора
  .Materialize()
  .Run(Console.WriteLine);
{% endhighlight %}

Вывод:

```
OnNext(1)
OnNext(2)
OnCompleted()
```
В случае итераторов:

{% highlight C# %}
static IEnumerable<int> YieldFinally()
{
    try
    {
        yield return 1;
        yield return 2;
        yield return 3;
    }
    finally { Console.WriteLine("=> finally"); }
}

static void Main(string[] args)
{
    YieldFinally()
        .Take(2)
        .Materialize()
        .Run(Console.WriteLine);
}
{% endhighlight %}

Получаем:

```
OnNext(1)
OnNext(2)
=> finally
OnCompleted()
```
Ещё одна плохая новость в том, что исправить это вовсе не представляется возможным, так как компилятор C# из Async CTP просто не генерирует для `async`-методов необходимый код, рассчитанный на такое поведение (грубо говоря, нельзя за`Dispose`'ить асинхронный метод во время `await`'а). Можно защитить пользователя от таких ситуаций, бросая исключение, если `Dispose` вызывают до окончания перебора итератора (к сожалению, данный код не защищает от вызова `Dispose` итератом самому себе):

{% highlight C# %}
public void Dispose()
{
    if (this.moveNext != null)
        throw new InvalidOperationException(
            "Early disposing is not supported.");
}
{% endhighlight %}

Если в вашем итераторе нету `try-finally` или `using`, то реализация совсем ничем не отличается от обычного итератора C# 2.0. А так как `async`-методы в виде лямбда-выражений допускают вложенность, то можно издеваться над мозгом сколько угодно вложенными друг в друга итераторами:

{% highlight C# %}
Iterator.Of<int>(async yield =>
{
    foreach (var x in
        Iterator.Of<int>(async y =>
        {
            await y(1);
            await y(2);
            await y(3);
        }))
    {
        await yield(x + 1);
        await yield(x + 2);
    }
})
.Run(Console.WriteLine);
{% endhighlight %}

Таким образом, мы обнаружили очень большую схожесть между трансформациями `async`-методов из Async CTP и давно имеющимися в C# `yield return`-итераторами, что позволяет выражать одну фичу через другую. Естественно, данная реализация приведена только в ознакомительных целях и серъёзного применения не имеет (из-за описанных выше проблем с `finally`).