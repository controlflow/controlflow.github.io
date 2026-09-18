---
layout: post
title: "INotifyPropertyChanged via ContextBoundObject"
date: 2010-11-28 15:12:00
author: Aleksandr Shvedov
tags: csharp dotnet remoting contextboundobject marshalbyrefobject inotifypropertychanged
---
There are many ways to reduce the boilerplate involved in implementing `System.ComponentModel.INotifyPropertyChanged`. Here is an experiment using `System.ContextBoundObject`, a .NET class that derives from `System.MarshalByRefObject` and allows calls to its instances to be intercepted through the .NET Remoting infrastructure:

```c#
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.Remoting.Activation;
using System.Runtime.Remoting.Contexts;
using System.Runtime.Remoting.Messaging;
using System.Threading;

namespace SomeNamespace
{

using PropertyCache = Dictionary<MethodBase, PropertyChangedEventArgs>;

[NotifyPropertyChanged]
public abstract class ViewModelBase
  : ContextBoundObject, INotifyPropertyChanged
{
  public event PropertyChangedEventHandler PropertyChanged;

  private static readonly object cacheSync = new object();
  private static readonly Dictionary<Type, PropertyCache> cache = new Dictionary<Type, PropertyCache>();

  private static PropertyCache Resolve(Type type)
  {
    PropertyCache props;
    lock (cacheSync)
    {
      if (cache.TryGetValue(type, out props)) return props;
    }

    props = new PropertyCache();
    foreach (var property in type.GetProperties())
    {
      if (!property.CanWrite) continue;

      var notify = Attribute.GetCustomAttribute(
        property, typeof(NotifyAttribute)) as NotifyAttribute;

      if (notify == null || notify.Enabled)
      {
        props.Add(
          property.GetSetMethod(),
          new PropertyChangedEventArgs(property.Name));
      }
    }

    lock (cacheSync)
    {
      if (!cache.ContainsKey(type)) cache.Add(type, props);
    }

    return props;
  }

  [AttributeUsage(AttributeTargets.Property)]
  public sealed class NotifyAttribute : Attribute
  {
    public NotifyAttribute(bool enabled)
    {
      Enabled = enabled;
    }

    public bool Enabled { get; private set; }
  }

  [AttributeUsage(AttributeTargets.Class)]
  private sealed class NotifyPropertyChangedAttribute : ContextAttribute, IContributeObjectSink
  {
    public NotifyPropertyChangedAttribute()
      : base("NotifyPropertyChanged")
    {
    }

    public override void GetPropertiesForNewContext(IConstructionCallMessage message)
    {
      message.ContextProperties.Add(this);
    }

    IMessageSink IContributeObjectSink.GetObjectSink(MarshalByRefObject obj, IMessageSink nextSink)
    {
      return new NotifySink((ViewModelBase) obj, nextSink);
    }
  }

  private sealed class NotifySink : IMessageSink
  {
    private readonly IMessageSink next;
    private readonly ViewModelBase target;
    private readonly PropertyCache props;

    public NotifySink(ViewModelBase target, IMessageSink next)
    {
      this.next = next;
      this.target = target;
      this.props = Resolve(target.GetType());
    }

    public IMessageSink NextSink { get { return this.next; } }

    public IMessageCtrl AsyncProcessMessage(IMessage msg, IMessageSink sink)
    {
      throw new NotSupportedException(
        "AsyncProcessMessage is not supported.");
    }

    public IMessage SyncProcessMessage(IMessage msg)
    {
      var call = msg as IMethodCallMessage;
      if (call != null)
      {
        PropertyChangedEventArgs e;
        if (this.props.TryGetValue(call.MethodBase, out e))
        {
          var handler = this.target.PropertyChanged;
          if (handler != null) handler(target, e);
        }
      }

      return this.next.SyncProcessMessage(msg);
    }
  }
}
```

Usage:

```c#
public class FooViewModel : ViewModelBase
{
  public string Foo { get; set; }
  public string Bar { get; set; }

  [Notify(false)]
  public string Baz { get; set; }
}

static class Program
{
  private static void Main()
  {
    var vm = new FooViewModel();

    vm.PropertyChanged += (_, e) =>
    {
      Console.WriteLine(e.PropertyName + " changed!");
    };

    vm.Foo = "foo";
    vm.Bar = "bar";
    vm.Baz = "baz";
  }
}
}
```

A few details are worth examining:

* `[NotifyPropertyChanged]` is defined as a private nested class and applied to its own containing type.
* `[Notify]` is defined as a public nested class. This makes it available by its short name in IntelliSense within classes derived from `ViewModelBase`. Outside that scope, it needs to be qualified as `[ViewModelBase.Notify]`.
* `PropertyChangedEventArgs` instances are created once per cached property and reused for subsequent notifications.

This approach has two substantial drawbacks:

* Performance: this approach was three orders of magnitude slower than raising the event directly. Intercepting calls through .NET Remoting carries considerable overhead.
* Debugging: instances of classes derived from `ViewModelBase` are accessed through a *transparent proxy*. In the version of Visual Studio used for this experiment, the debugger could not inspect their fields and properties.

This code is an illustration of what the .NET Remoting infrastructure can do. Given the performance and debugging costs, I would not use it in production.