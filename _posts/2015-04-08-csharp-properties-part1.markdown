---
layout: post
title: "Design and evolution of properties in C# (part 1)"
date: 2015-04-08 17:52:00
author: Aleksandr Shvedov
tags: csharp properties design
---

The idea for this post came from an ordinary work task — supporting the new features of C# 6.0 in ReSharper. As usual, tasks in ReSharper turned out to be 5-10 times more complex than they initially seemed. A particular headache was supporting the new features of properties in C# 6.0, as the language changes affected a lot of existing functionality (not always in an obvious way). The revisions took several months, sometimes forcing us to rewrite some refactorings almost entirely (specifically, the "Convert property to auto-property" refactoring), which made me wonder — why is everything *so complicated* in the world of C# properties? How did it happen that working with C# properties in IDE tools requires keeping track of so much knowledge about them? Do regular programmers feel this "complexity"?

So today, I propose we discuss the concept of "properties" in detail using the C# language, starting from its very first version, reflect a bit on programming language design, where this design might be heading, and whether anything can be fixed.

## A Crash Course on Properties

### What are they, anyway?

Let's go back to the days of C# 1.0 and look at the definition of a canonical DTO class encapsulating some data. Unlike Java, class declarations in C# could contain not only fields/methods/classes, but also another type of class member — property declarations:

```c#
class Person
{
  private string _name;

  public Person(string name)
  {
    _name = name;
  }

  // property declaration:
  public string Name
  {
    get { return _name; }
    set { _name = value; }
  }
}

// property usage:
Person person = new Person();
person.Name = "Alex";
Console.WriteLine(person.Name);
person.Name += " the cat";
```

Properties are class members that have a name and type and also contain declarations for "accessors". Accessors are somewhat like method declarations, except for the explicit type of return values and the list of formal parameters. There are two kinds of property accessors — getters and setters, which are called when reading and writing to a property, respectively. At the time, this might have seemed like an elegant language feature compared to the "getter/setter" methods in Java (which are still used in 2015):

```java
class Person {
  private String _name;

  public String getName() {
    return _name;
  }

  public void setName(String value) {
    _value = value;
  }
}

Person person = new Person();
person.setName("Alex");
Console.WriteLine(person.getName());
person.setName(person.getName() + " the cat");
```

### Motivation

So, why do we need properties at all? The fact is that in high-level languages like Java and C#, class fields are relatively low-level constructs<sup>1</sup>. Accessing a field just reads or writes a memory area of some known size at a certain offset, statically known to the runtime. This low-level nature of fields leads to a few problems:

* There is no unified "interface" between different fields or fields of different types (for example, like a pointer to executable code), which prevents polymorphic access (writing code abstracted from knowing the exact type of the field it is accessing);
* There is no way to intercept accesses to a field to perform additional consistency checks or enforce class invariants. In practice, this means you can't debug a program by intercepting read/write access to fields via breakpoints.

Moreover, experience shows that in classes it’s often convenient to expose data externally without having it stored in state — i.e., computing data based on a rule every time it’s accessed, retrieving it from some internal object, and so on.

All these issues can be solved using existing language features — by introducing a couple of methods to access a field's value, implementing these methods as members of an interface, or executing arbitrary validation code before or after writing:

```c#
interface INamedPerson
{
  string GetName();
  SetName(string value);
  int GetYear();
}

class Person : INamedPerson
{
  private string _name;

  public string GetName() { return _name; }

  public void SetName(string value)
  {
    if (value == null) throw new ArgumentNullException("value");
    _value = value;
  }

  public int GetYear()
  {
    return DateTime.Now.Year;
  }
}
```

Why is this solution inconvenient?

* We lose the familiar syntax for accessing field data:

```c#
foo.Value += 42;
// vs
foo.SetValue(foo.GetValue() + 42);
```

* In the program, there is no real expression showing that the three entities — the field and the two methods — are somehow *related*. Methods and fields can have different visibility levels, names, static and virtual modifiers.
* To hint at their common relation, we’ve named the three entities with the substring "name" in their names. During refactoring, we’ll have to update all three names. Similarly with the data type mention. Such naming conventions simplify life in Java but are merely recommendations (the compiler won’t enforce them).

### Solution using properties

Let’s take the code example above and rewrite it using C# property declarations:

```c#
interface INamedPerson
{
  string Name { get; set; }
  int Year { get; }
}

class Person : INamedPerson
{
  private string _name;

  public string Name
  {
    get { return _name; }
    set
    {
      if (value == null) throw new ArgumentNullException("value");
      _name = value;
    }
  }

  public int Year
  {
    get { return DateTime.Now.Year; }
  }
}
```

The code is still quite verbose, but properties bring certain conveniences:

* The bodies of the accessors are syntactically combined into one block, meaning they logically share the same visibility level, static and virtual modifiers;
* The substring "name" now appears in the declarations only twice, just like the `String` type. The `value` parameter in the `set` accessor is implicitly declared, saving a bit of code;
* The property access syntax is the same as the familiar and simple syntax for field access, which also makes it much easier to manually encapsulate a field into a property (without automated refactorings);
* The property might not even have an underlying field, and the accessor bodies can contain arbitrary code;
* Although accessors still compile into method bodies (`string get_Name()` and `set_Name(string value)`), the metadata stores a special record about the property as a single entity (similar to events in C#). Thus, the concept of a "property" exists for the runtime, not just as a compiler entity. As a result, properties can be tagged with CLI attributes as a single entity, which has numerous practical applications.

No matter how hard I tried to structure further reasoning, it turned out that the rest was just a list of advantages and disadvantages of properties in general and the design of properties specifically in the first version of C#.

### Set-only properties

There’s not much to discuss here — C# should never have allowed properties with only a `set` accessor:

```c#
class Foo
{
  public int Property
  {
    set { SendToDeepSpace(value); }
  }
}
```

Programming language design can be compared to a multidimensional optimization problem. Finding a local maximum for a function with many variables (flexibility, functionality, canonicality, syntactical beauty, etc.) might make it seem like the chosen design is canonical enough. However, there’s always the chance that by sacrificing the maximum in one dimension, you can find a more sensible optimum across all dimensions.

For example, forbidding the declaration of properties with only a `set` accessor might seem like a natural "patch" from the perspective of language specification beauty, an artificial restriction that disrupts the symmetry between different kinds of accessors<sup>2</sup> (with `get` accessors becoming mandatory).

On the other hand, if such obviously strange entities (set-only properties) are not prohibited, real messy code starts to appear (I've encountered such properties a couple of times). If you encounter such properties and don’t understand why their value isn’t visible in the debugger, you start to appreciate not the canonicality of the property definition in the spec, but the number of restrictions the compiler imposes.

### Different access kinds

A simple programming language is the one where you can see a variable `foo` being used in code and always know whether it’s being read or written. But long ago, the C programming language introduced these mutants:

```c#
variable ++;
variable += 42;
```

So a new *kind* of usage emerges — read/write access<sup>3</sup>. Since C# aims to syntactically eliminates the difference between using properties and using fields, such operators are also allowed for (writable) properties, compiling into sequential calls of `get` and `set` accessors:

```c#
++ person.Age;
// is
person.set_Age(person.get_Age() + 1);
```

It seems great that this works — after all, that’s what a high-level language is supposed to do: hide low-level implementation details, such as properties being method calls. The problem is that C# has another source of simultaneous read/write usage — `ref` parameters:

```c#
void M(ref int x)
{
  x += 42;
}

int x = 0;
M(ref x); // read-write usage
```

Unfortunately, `ref`/`out` parameters in C# are as low-level as fields. The runtime treats `ref`/`out` parameters as special managed reference types, different from regular unmanaged pointers only in their disallowance of arithmetic operations and the awareness of GC about objects pointed to by such references.

Due to the inability to turn the two property accessor methods into a single pointer to a mutable memory region, the C# compiler simply doesn’t allow passing properties to `ref`/`out` parameters. This is rarely needed in practice, but it does seem like a "spontaneous symmetry breaking" in the language. Interestingly, another .NET language — VisualBasic.NET — hides the difference between properties and fields from the user:

```vb
Sub F(ByRef x As integer)
  x += 1
End Sub

Interface ISomeType
  Property Prop as integer
End Interface

Dim i As ISomeType = ...
F(i.Prop) ' OK
```

Essentially, VB.NET allows passing any expressions as `byref` parameters, automatically creating a temporary local variable and passing its address. If a mutable property is passed as a `byref` argument, VB.NET automatically assigns the value to the property from the temporary variable only at the end of the call. There’s a very small chance (but still a chance) that a method with a `byref` parameter might somehow depend on the actual value passed to it, which could turn this convenience into a trap.

But there are enough traps already: for example, if you take `i.Prop` from the example above and put it in parentheses, the property assignment will no longer happen (since a temporary value of the expression inside the parentheses is passed instead of the actual property *as an address*). Additionally, the assignment to the property will not occur if an exception occurs after assigning the `byref` parameter in the method. It’s unclear whether these pitfalls are worth the lost universality of the language.

[To be continued...]({% post_url 2015-04-08-csharp-properties-part2 %})

<sup>1</sup> In the CLR, reading fields of `MarshalByReference` objects is actually always virtual (until they are passed to `ref`/`out` parameters).

<sup>2</sup> In C#, there are already other types of class members with accessors — *events* — for which the compiler always requires both accessors (`add` and `remove`) to be defined.

<sup>3</sup> In reality, I am not mentioning other types of uses for entities in C# — usages from XML documentation, usage of entity names in the `nameof()` operator from C# 6.0, and "partial" read/write uses when working with value types:

```c#
   Point point;

   point.X = 42;            var x = point.X;
// |     |__ write                  |     |__ read
// |________ partial write          |________ partial read
```