---
layout: post
title: "Особенности компиляции анонимных делегатов/лямбда-выражений в C#"
date: 2011-08-02 14:45:17
categories: 8381759155
tags: csharp lambda-expressions anonymous delegate clr closure
---
Я думаю, что большинство из .NET-программистов интересовалось как именно устроен синтаксический сахар анонимных делегатов в C# 2.0, а так же лямбда-выражений, появившихся немного позже. В простых случаях анонимные делегаты превращаются в статические методы с приватным уровнем доступа и непроизносимым именем (специально чтобы вы не могли набрать такое же имя в C#), например:

{% highlight C# %}
static void HookCancelPress()
{
  Console.CancelKeyPress += delegate { Console.WriteLine("Пока!"); };
}
{% endhighlight %}

Компилируется как обычный приватный статический метод (обратите внимание на возможность опустить список формальных параметров в анонимных делегатах C# 2.0):

{% highlight C# %}
static void HookCancelPress()
{
  Console.CancelKeyPress +=
    new ConsoleCancelEventHandler(Program.<Main>b__0);
}

[CompilerGenerated]
static void <Main>b__0(object param0, ConsoleCancelEventArgs param1)
{
  Console.WriteLine("пока!");
}
{% endhighlight %}

Интересное начинается тогда, когда анонимный делегат/лямбда-выражение начинается замыкаться на внешние переменные (включая параметры методов), тем самым продляя их время жизни. В этих случаях компилятор C# генерирует closure-класс (я предпочитаю его так называть) и переменная, на которую происходит замыкание, становится полем этого класса (далее в примерах кода я заменял названия closure-классов на более читаемые):

{% highlight C# %}
static IEnumerable<int> MultipleBy(
    this IEnumerable<int> source, int multiplier)
{
  return source.Select(x => checked(x * multiplier));
}
{% endhighlight %}

Компилируется в (обратите внимание на публичность полей closure-класса):

{% highlight C# %}
[CompilerGenerated]
sealed class DisplayClass1
{
  public int multiplier;

  public int <MultipleBy>b__0(int x)
  {
    return checked(x * this.multiplier);
  }
}

static IEnumerable<int> MultipleBy(
    this IEnumerable<int> source, int multiplier)
{
  DisplayClass1 closure = new DisplayClass1();
  closure.multiplier = multiplier;
  return source.Select(new Func<int, int>(closure.<MultipleBy>b__0));
}
{% endhighlight %}

Так как время жизни делегата вовсе неизвестно, то переменные, захваченные в замыкание, приходится переносить в кучу (в поле closure-класса, память под который выделяется в куче, а время жизни контроллируется сборщиком мусора). Обратите внимание, что на доступ к полю closure-класса, заменяются не только обращения к переменным внутри анонимного делегата, но и в самом методе. Это необходимо из-за того, что C# у нас язык императивный с изменяемыми переменнами, а значит должна быть возможность изменять переменные внутри делегатов и внешний метод должен “видеть” эти изменения:

{% highlight C# %}
static void MutableClosure()
{
  int value = 0;
  Action f = delegate { value++; };
  f();
  Console.WriteLine("value = {0}", value); // value = 1
}
{% endhighlight %}

Превращается в:

{% highlight C# %}
[CompilerGenerated]
sealed class DisplayClass1
{
  public int value;
  public void <Foo>b__0() { this.value++; }
}

static void MutableClosure()
{
  DisplayClass1 closure = new DisplayClass1();
  closure.value = 0;
  Action f = new Action(closure.<Foo>b__0);
  f();
  Console.WriteLine("value = {0}", closure.value /* <--- */);
}
{% endhighlight %}

Таким образом, переменная, взятая в замыкание, никогда не выделяется на стеке и обладает небольшим оверхедом при доступе, так как является полем closure-класса. Существуют вырожденные случаи, когда в замыкание попадают только поля класса:

{% highlight C# %}
class FooValue
{
  readonly int value;

  public FooValue(int value)     { this.value = value; }
  public Func<int, int> GetBar() { return x => x * value; }
}
{% endhighlight %}

В этих случаях делегат очень удобно компилируется в метод уровня экземпляра:

{% highlight C# %}
class FooValue
{
  readonly int value;

  public FooValue(int value) { this.value = value; }

  public Func<int, int> GetBar() 
  {
    return new Func<int, int>(this.<GetBar>b__0);
  }

  [CompilerGenerated]
  private int <GetBar>b__0(int x) { return x * this.value; }
}
{% endhighlight %}

За счёт этого же эффекта, несколько вложенных определений анонимных методов:

{% highlight C# %}
static void Bar()
{
  var value = 1;
  Action f = delegate {
    Action g = delegate {
      Action h = delegate { value++; };
    };
  };
}
{% endhighlight %}

Могут эффективно компилироваться всего лишь в один closure-класс:

{% highlight C# %}
[CompilerGenerated]
sealed class DisplayClass3
{
  public int value;

  public void <Bar>b__0() { new Action(this.<Bar>b__1); }
  public void <Bar>b__1() { new Action(this.<Bar>b__2); }
  public void <Bar>b__2() { this.value++; }
}

static void Bar()
{
  DisplayClass3 closure = new DisplayClass3();
  closure.value = 1;
  new Action(closure.<Bar>b__0);
}
{% endhighlight %}

Но стоит взять в замыкание ещё одну переменную, как трансформация лямбда-выражения усложняется:

{% highlight C# %}
class FooValue
{
  readonly int value;

  public FooValue(int value) { this.value = value; }

  public Func<int, int> GetBar(int delta) 
  {
    return x => x * value + delta;
  }
}
{% endhighlight %}

Что вызывает генерацию closure-класса:

{% highlight C# %}
class FooValue
{
  [CompilerGenerated]
  sealed class DisplayClass1
  {
    public FooValue __this;
    public int delta;

    public int <GetBar>b__0(int x)
    {
      return x * this.__this.value + this.delta;
    }
  }

  readonly int value;

  public FooValue(int value) { this.value = value; }

  public Func<int, int> GetBar(int delta)
  {
    DisplayClass1 closure = new DisplayClass1();
    closure.delta = delta;
    closure.__this = this;
    return new Func<int, int>(closure.<GetBar>b__0);
  }
}
{% endhighlight %}

То есть в замыкание берутся две переменные - `delta` и `this`. Обратите внимание, что поле `value` объявлено как `readonly`, а значит его значение теоретически можно было бы взять в замыкание вместо ссылки на весь объект `FooValue` (и объект мог бы быть успешно собран сборщиком мусора вне зависимости от существования замыкания). Однако C# так не делает, так как анонимный метод может быть создан в конструкторе ещё до инициализации поля `value`.

Неприятные эффекты начинаются тогда, когда несколько анонимных делегатов в одном методе захватывают одну и ту же переменную:

{% highlight C# %}
static Func<int> SharedClosure()
{
  var xs = new int[10000000];
  var index = 0;

  Action notEvenUsed = () => Console.WriteLine(xs[index]);
  return () => index++;
}
{% endhighlight %}

Компилятор C# разделяет closure-класс между двумя анонимными делегатами:

{% highlight C# %}
[CompilerGenerated]
sealed class DisplayClass2
{
  public int[] xs; // <-- !!!!!
  public int index;

  public void <SharedClosure>b__0()
  {
    Console.WriteLine(this.xs[this.index]);
  }

  public int <SharedClosure>b__1()
  {
    return this.index++;
  }
}

static Func<int> SharedClosure()
{
  DisplayClass2 closure = new DisplayClass2();
  closure.xs = new int[10000000];
  closure.index = 0;
  new Action(closure.<SharedClosure>b__0);
  return new Func<int>(closure.<SharedClosure>b__1);
}
{% endhighlight %}

Видите проблему? Не смотря на то, что один делегат тут даже вовсе не используется, второй делегат продляет жизнь не только переменной `value`, на которую он замыкается, но ещё и хранит в себе переменную `xs`! Таким образом могут появляться трудноотлавливаемые утечки памяти, ведь пользователь никак не ожидает, что делегат сохраняет в себе ссылку на переменную, которую он вовсе не брал в замыкание. Правильной трансформацией было бы использование двух closure-классов: первый хранил бы в себе переменную `index`, а второй - ссылку на первый closure-класс и переменную `xs`.

Продолжение следует…