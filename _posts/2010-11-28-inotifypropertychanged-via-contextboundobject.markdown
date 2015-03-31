---
layout: post
title: "INotifyPropertyChanged via ContextBoundObject"
date: 2010-11-28 15:12:00
categories: 1713655006
tags: csharp dotnet remoting contextboundobject marshalbyrefobject inotifypropertychanged
---
Мне было нечего делать и к бесчисленному количеству вариантов удобной реализации классами интерфейса `System.ComponentModel.INotifyPropertyChanged` я набросал вариант с использованием такого загадочного класса .NET, как `System.ContextBoundObject`, являющегося наследником `System.MarshalByRefObject` и предоставляющего интерфейс для перехвата обращения к таким объектам. Реализация (прошу прощения за отсутствие комментариев):

{% highlight C# %}
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.Remoting.Activation;
using System.Runtime.Remoting.Contexts;
using System.Runtime.Remoting.Messaging;
using System.Threading;

namespace SomeNamespace {

using PropertyCache =
  Dictionary<MethodBase, PropertyChangedEventArgs>;

[NotifyPropertyChanged]
public abstract class ViewModelBase
    : ContextBoundObject, INotifyPropertyChanged
{
  public event PropertyChangedEventHandler PropertyChanged;

  static readonly object cacheSync = new object();
  static readonly Dictionary<Type, PropertyCache>
    cache = new Dictionary<Type, PropertyCache>();

  static PropertyCache Resolve(Type type)
  {
    PropertyCache props;
    lock (cacheSync)
      if (cache.TryGetValue(type, out props)) return props;

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
      if (!cache.ContainsKey(type)) cache.Add(type, props);

    return props;
  }

  [AttributeUsage(AttributeTargets.Property)]
  public sealed class NotifyAttribute : Attribute
  {
    public NotifyAttribute(bool enabled) { Enabled = enabled; }

    public bool Enabled { get; private set; }
  }

  [AttributeUsage(AttributeTargets.Class)]
  sealed class NotifyPropertyChangedAttribute
    : ContextAttribute, IContributeObjectSink
  {
    public NotifyPropertyChangedAttribute()
      : base("NotifyPropertyChanged") { }

    public override void GetPropertiesForNewContext(
      IConstructionCallMessage message)
    {
      message.ContextProperties.Add(this);
    }

    IMessageSink IContributeObjectSink.GetObjectSink(
      MarshalByRefObject obj, IMessageSink nextSink)
    {
      return new NotifySink((ViewModelBase) obj, nextSink);
    }
  }

  sealed class NotifySink : IMessageSink
  {
    readonly IMessageSink next;
    readonly ViewModelBase target;
    readonly PropertyCache props;

    public NotifySink(ViewModelBase target, IMessageSink next)
    {
      this.next = next;
      this.target = target;
      this.props = Resolve(target.GetType());
    }

    public IMessageSink NextSink
    {
      get { return this.next; }
    }

    public IMessageCtrl AsyncProcessMessage(
        IMessage msg, IMessageSink sink)
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

public class FooViewModel : ViewModelBase
{
  public string Foo { get; set; }
  public string Bar { get; set; }

  [Notify(false)]
  public string Baz { get; set; }
}

static class Program
{
  static void Main()
  {
    var vm = new FooViewModel();

    vm.PropertyChanged += (_, e) =>
      Console.WriteLine(e.PropertyName + " changed!");

    vm.Foo = "foo";
    vm.Bar = "bar";
    vm.Baz = "baz";
  }
}}
{% endhighlight %}

Тут есть интересные моменты:

* Атрибут `[NotifyPropertyChanged]` определяется приватным вложенным классом и применяется к типу, внутри определения которого он определён.
* Атрибут `[Notify]` определяется публичным вложенным классом, что даёт интересный эффект: внутри определений наследников `ViewModelBase` данный атрибут «видно» в списке автодополнения *IntelliSense*, а в других местах - нет, так как требуется указание полного имени: `[ViewModelBase.Notify]`.
* Экземпляры классов `PropertyChangedEventArgs` создаются только один раз и переиспользуются при всех изменениях свойств.

К сожалению, у данного костыля есть два *существенных* недостатка:

* Всё это дело жестоко тормозит: на три (!) порядка медленнее, чем реализация «руками». Что делать, но за использование инфраструктуры .NET Remoting приходится платить такую цену.
* Самый главный недостаток: все наследники `ViewModelBase` невозможно отлаживать, так как их экземпляры представляют собой *transparent proxy* и в отладчике VisualStudio просто невозможно посмотреть содержимое полей и свойств этих экземпляров. Есть идеи как это можно попробовать «запилить», но пока не вышло.

Код я привёл лишь в целях ознакомления с возможностями инфраструктуры .NET Remoting, пожалуйста, никогда его не используйте для решения реальных задач.