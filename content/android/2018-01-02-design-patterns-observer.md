---
title: "设计模式之观察者模式"
layout: page
date: 2018-01-02 21:22
---

[TOC]

### 定义

观察者模式(Observer Pattern)：对象间的一种一对多依赖关系，使得每当一个对象状态发生改变时，其相关依赖对象皆得到通知并被自动更新。观察者模式又叫做发布-订阅（Publish/Subscribe）模式、模型-视图（Model/View）模式、源-监听器（Source/Listener）模式或从属者（Dependents）模式。

观察者模式是一种对象行为型模式。

###  RegistrantList消息处理机制

Android Telephony中大量使用RegistrantList进行消息处理，它是观察者模式的一种实现方式。

![](/wiki/static/images/RegistrantList.png)

其中：

- RegistrantList是通知者
- Registrant是观察者

也是一种一对多的依赖关系，每一个通知者可以对应一个或多个观察者，当事件列表有更新时，观察者列表中的所有对象都会收到通知。

#### 注册观察者

在android中注册观察者的方法一般都是类似于：registerXXX

```java
@IccRecords.java
protected RegistrantList mRecordsLoadedRegistrants = new RegistrantList();
public void registerForRecordsLoaded(Handler h, int what, Object obj) {
    if (mDestroyed.get()) {
        return;
    }

    Registrant r = new Registrant(h, what, obj);
    mRecordsLoadedRegistrants.add(r);

    if (mRecordsToLoad == 0 && mRecordsRequested == true) {
        r.notifyRegistrant(new AsyncResult(null, null, null));
    }
}
```

这个函数的主要功能是：

- 创建一个Registrant
- 把Registrant（r）加入到RegistrantList（mRecordsLoadedRegistrants）中
- 当满足条件时发出通知

注册观察者形式比较简单，如下，只是调用上面的方法就可以了。

```java
@IccCardProxy.java
mIccRecords.registerForRecordsLoaded(this, EVENT_RECORDS_LOADED, null);
```

#### 发出通知

在满足一定条件的时候就发出通知，让注册观察者端进行处理相应的逻辑。

```java
@SIMRecords.java
mRecordsLoadedRegistrants.notifyRegistrants(
            new AsyncResult(null, null, null));
```

#### 响应通知

当注册观察者端接收到通知之后，就在对应的`handleMessage`中进行处理。比如在前面注册的是**EVENT_RECORDS_LOADED**，所以在对应的`handleMessage`中可以看到如下代码。

```java
@IccCardProxy.java
public void handleMessage(Message msg) {
    switch (msg.what) {
        case EVENT_RECORDS_LOADED:
            // Update the MCC/MNC.
            if (mIccRecords != null) {
                Phone currentPhone = PhoneFactory.getPhone(mPhoneId);
                String operator = currentPhone.getOperatorNumeric();
                log("operator=" + operator + " mPhoneId=" + mPhoneId);

                if (!TextUtils.isEmpty(operator)) {
                    mTelephonyManager.setSimOperatorNumericForPhone(mPhoneId, operator);
                    String countryCode = operator.substring(0,3);
                    if (countryCode != null) {
                        mTelephonyManager.setSimCountryIsoForPhone(mPhoneId,
                                MccTable.countryCodeForMcc(Integer.parseInt(countryCode)));
                    } else {
                        loge("EVENT_RECORDS_LOADED Country code is null");
                    }
                } else {
                    loge("EVENT_RECORDS_LOADED Operator name is null");
                }
            }
            if (mUiccCard != null && !mUiccCard.areCarrierPriviligeRulesLoaded()) {
                mUiccCard.registerForCarrierPrivilegeRulesLoaded(
                        this, EVENT_CARRIER_PRIVILEGES_LOADED, null);
            } else {
                onRecordsLoaded();
            }
            break;
        default:
            loge("Unhandled message with number: " + msg.what);
            break;
    }
}
```

然后回去对应的Message中去进行相应的处理。

#### 取消注册

```java
@IccRecords.java
public void unregisterForRecordsLoaded(Handler h) {
    mRecordsLoadedRegistrants.remove(h);
}
```

取消注册也比较简单，只是调用下`remove`方法就可以了。

### Registrant介绍

```java
public class Registrant
{
    WeakReference   refH;
    int             what;
    Object          userObj;
}
```

观察中定义了三个成员对象，用以保存调用者的信息。主要的功能是用于发送通知。

```java
internalNotifyRegistrant (Object result, Throwable exception)
{
    Handler h = getHandler();
    if (h == null) {
        clear();
    } else {
        Message msg = Message.obtain();
        msg.what = what;
        msg.obj = new AsyncResult(userObj, result, exception);
        h.sendMessage(msg);
    }
}
```

- 当`Handler`不为空的时候，通过`sendMessage`方法把消息发送给调用者。

### RegistrantList具体实现

前面我们介绍了下RegistrantList消息处理机制，以android中的一次调用进行举例说明，了解了如何注册、通知、去注册，明白了消息的处理逻辑。这里重点介绍下RegistrantList的具体实现。

```java
public class RegistrantList
{
    ArrayList   registrants = new ArrayList();
  ...
}
```

RegistrantList中就定义了一个`ArrayList`类型的成员变量用来维护所有的观察者。

#### 添加观察者

```java
public synchronized void
add(Registrant r)
{
    removeCleared();
    registrants.add(r);
}

public synchronized void
removeCleared()
{
    for (int i = registrants.size() - 1; i >= 0 ; i--) {
        Registrant  r = (Registrant) registrants.get(i);
        
        if (r.refH == null) {
            registrants.remove(i);
        }
    }
}
```

- 清除数组列表中所有`Handler`为空的对象
- 把新的观察者加入到数组列表中

#### 发送通知

```java
private synchronized void
internalNotifyRegistrants (Object result, Throwable exception)
{
   for (int i = 0, s = registrants.size(); i < s ; i++) {
        Registrant  r = (Registrant) registrants.get(i);
        r.internalNotifyRegistrant(result, exception);
   }
}
```

- 遍历整个数组列表，分别调用观察者的方法，把消息发送给调用者。

#### 取消注册

```java
public synchronized void
remove(Handler h)
{
    for (int i = 0, s = registrants.size() ; i < s ; i++) {
        Registrant  r = (Registrant) registrants.get(i);
        Handler     rh;
        rh = r.getHandler();
        /* Clean up both the requested registrant and
         * any now-collected registrants
         */
        if (rh == null || rh == h) {
            r.clear();
        }
    }
    removeCleared();
}
```

- 遍历整个数组列表，把所有的观察者从列表中删除。

