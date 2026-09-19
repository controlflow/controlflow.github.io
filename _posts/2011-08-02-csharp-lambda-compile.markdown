---
layout: post
title: "How lambda expressions are compiled in C#"
date: 2011-08-02 14:45:17
author: Aleksandr Shvedov
tags: csharp lambda-expressions anonymous delegate clr closure
---
Most .NET developers have probably wondered how the syntactic sugar of anonymous methods in C# 2.0, and the lambda expressions introduced later, actually works. In simple cases, anonymous methods become private static methods with compiler-generated names that cannot be written as identifiers in C#. For example:

```c#
private static void HookCancelPress()
{
  Console.CancelKeyPress += delegate { Console.WriteLine("Goodbye!"); };
}
```

The anonymous method becomes an ordinary private static method. Notice that C# 2.0 allows the parameter list of an anonymous method to be omitted:

```c#
private static void HookCancelPress()
{
  Console.CancelKeyPress += new ConsoleCancelEventHandler(Program.<Main>b__0);
}

[CompilerGenerated]
private static void <Main>b__0(object param0, ConsoleCancelEventArgs param1)
{
  Console.WriteLine("Goodbye!");
}
```

Things get more interesting when an anonymous method or lambda expression captures variables from an enclosing scope, including method parameters, extending their lifetime. In these cases, the C# compiler generates what I call a closure class, and each captured variable becomes a field of that class. In the examples below, I have replaced the generated closure class names with more readable ones:

```c#
private static IEnumerable<int> MultipleBy(this IEnumerable<int> source, int multiplier)
{
  return source.Select(x => checked(x * multiplier));
}
```

This compiles to the following code. Notice that the fields of the closure class are public:

```c#
[CompilerGenerated]
sealed class DisplayClass1
{
  public int multiplier;

  public int <MultipleBy>b__0(int x)
  {
    return checked(x * this.multiplier);
  }
}

private static IEnumerable<int> MultipleBy(this IEnumerable<int> source, int multiplier)
{
  DisplayClass1 closure = new DisplayClass1();
  closure.multiplier = multiplier;
  return source.Select(new Func<int, int>(closure.<MultipleBy>b__0));
}
```

Since the lifetime of a delegate is not known in advance, captured variables have to move to the heap: they become fields of a closure object whose lifetime is managed by the garbage collector. Accesses to these variables are replaced with field accesses both inside the anonymous method and in the enclosing method. This is necessary because C# is an imperative language with mutable variables: the delegate must be able to change a captured variable, and the enclosing method must see that change:

```c#
private static void MutableClosure()
{
  int value = 0;
  Action f = delegate { value++; };
  f();
  Console.WriteLine("value = {0}", value); // value = 1
}
```

This becomes:

```c#
[CompilerGenerated]
sealed class DisplayClass1
{
  public int value;
  public void <Foo>b__0() { this.value++; }
}

private static void MutableClosure()
{
  DisplayClass1 closure = new DisplayClass1();
  closure.value = 0;
  Action f = new Action(closure.<Foo>b__0);
  f();
  Console.WriteLine("value = {0}", closure.value /* <--- */);
}
```

A captured local is therefore stored in a closure object rather than on the stack, with a small overhead for field access. There is also a simpler case, where the anonymous method only accesses instance fields:

```c#
class FooValue
{
  private readonly int value;

  public FooValue(int value)
  {
    this.value = value;
  }

  public Func<int, int> GetBar()
  {
    return x => x * value;
  }
}
```

In this case, the anonymous method can simply become an instance method on the existing object:

```c#
class FooValue
{
  private readonly int value;

  public FooValue(int value)
  {
    this.value = value;
  }

  public Func<int, int> GetBar()
  {
    return new Func<int, int>(this.<GetBar>b__0);
  }

  [CompilerGenerated]
  private int <GetBar>b__0(int x)
  {
    return x * this.value;
  }
}
```

For a similar example, consider these nested anonymous methods:

```c#
private static void Bar()
{
  var value = 1;
  Action f = delegate
  {
    Action g = delegate
    {
      Action h = delegate { value++; };
    };
  };
}
```

These can be compiled using just one closure class:

```c#
[CompilerGenerated]
sealed class DisplayClass3
{
  public int value;

  public void <Bar>b__0() { new Action(this.<Bar>b__1); }
  public void <Bar>b__1() { new Action(this.<Bar>b__2); }
  public void <Bar>b__2() { this.value++; }
}

private static void Bar()
{
  DisplayClass3 closure = new DisplayClass3();
  closure.value = 1;
  new Action(closure.<Bar>b__0);
}
```

Capturing another variable makes the transformation more involved:

```c#
class FooValue
{
  private readonly int value;

  public FooValue(int value)
  {
    this.value = value;
  }

  public Func<int, int> GetBar(int delta)
  {
    return x => x * value + delta;
  }
}
```

This requires a closure class:

```c#
class FooValue
{
  [CompilerGenerated]
  private sealed class DisplayClass1
  {
    public FooValue __this;
    public int delta;

    public int <GetBar>b__0(int x)
    {
      return x * this.__this.value + this.delta;
    }
  }

  private readonly int value;

  public FooValue(int value)
  {
    this.value = value;
  }

  public Func<int, int> GetBar(int delta)
  {
    DisplayClass1 closure = new DisplayClass1();
    closure.delta = delta;
    closure.__this = this;
    return new Func<int, int>(closure.<GetBar>b__0);
  }
}
```

The closure captures both `delta` and `this`. Notice that `value` is a `readonly` field. In principle, the compiler could copy its value into the closure instead of retaining a reference to the entire `FooValue` object, allowing that object to be collected independently of the closure. However, C# does not do this: the anonymous method could be created in a constructor before `value` has been initialized.

An unfortunate side effect appears when several anonymous methods in the same method capture the same variable:

```c#
private static Func<int> SharedClosure()
{
  var xs = new int[10000000];
  var index = 0;

  Action notEvenUsed = () => Console.WriteLine(xs[index]);
  return () => index++;
}
```

The C# compiler shares one closure object between the two delegates:

```c#
[CompilerGenerated]
sealed class DisplayClass2
{
  public int[] xs; // keeps the array alive
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

private static Func<int> SharedClosure()
{
  DisplayClass2 closure = new DisplayClass2();
  closure.xs = new int[10000000];
  closure.index = 0;
  new Action(closure.<SharedClosure>b__0);
  return new Func<int>(closure.<SharedClosure>b__1);
}
```

Although the first delegate is never used, the returned delegate keeps both the captured variable `index` and the array referenced by `xs` alive. This can lead to memory retention that is difficult to track down: a delegate unexpectedly retains a reference to a variable it never uses. A better transformation would use two closure classes: one containing `index`, and another containing `xs` and a reference to the first closure object.

Continue with [How function values are compiled in F#]({{ site.baseurl }}/2011/08/03/fsharp-lambda-compile.html).