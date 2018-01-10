---
title: "Telephony之UICC架构"
date: 2018-01-08 17:51
---

[TOC]

## 总体设计

![](/wiki/static/images/UICC_architecture.png)

从图中可以看出，处理整个UICC的入口是在UiccController中。相当于Telephony中UICC的管家。

## 初始化流程

![](/wiki/static/images/UiccController_init.png)

## UiccController

UiccController的创建过程可以参考上图初始化流程，通过make方法初始化，注意只创建了**一个**UiccController对象。

### UiccController的功能

- 创建并提供`UiccCard`、`IccRecords`、`IccFileHandler`和`UiccCardApplication`对象
- 提供对sim卡状态的监听

### UiccController更新机制

```java
mCis[i].registerForIccStatusChanged(this, EVENT_ICC_STATUS_CHANGED, index);
mCis[i].registerForAvailable(this, EVENT_ICC_STATUS_CHANGED, index);
mCis[i].registerForNotAvailable(this, EVENT_RADIO_UNAVAILABLE, index);
mCis[i].registerForIccRefresh(this, EVENT_SIM_REFRESH, index);
```

`UiccController`构造函数中注册了4个监听器，依次看下这4个监听器要实现的功能。

这4个监听器都是在RIL的父类BaseCommands中实现的。

#### registerForIccStatusChanged

```java
public void registerForIccStatusChanged(Handler h, int what, Object obj) {
    Registrant r = new Registrant (h, what, obj);
    mIccStatusChangedRegistrants.add(r);
}
```

1、当Modem主动上报sim卡状态改变时触发

```java
public void simStatusChanged(int indicationType) {
    mRil.processIndication(indicationType);

    if (RIL.RILJ_LOGD) mRil.unsljLog(RIL_UNSOL_RESPONSE_SIM_STATUS_CHANGED);

    mRil.mIccStatusChangedRegistrants.notifyRegistrants();
}
```

2、处理sim卡PUK和PUK2码时触发

```java
...
protected RILRequest processResponse(RadioResponseInfo responseInfo) {
    switch (rr.mRequest) {
        case RIL_REQUEST_ENTER_SIM_PUK:
        case RIL_REQUEST_ENTER_SIM_PUK2:
            if (mIccStatusChangedRegistrants != null) {
                if (RILJ_LOGD) {
                    riljLog("ON enter sim puk fakeSimStatusChanged: reg count="
                            + mIccStatusChangedRegistrants.size());
                }
                mIccStatusChangedRegistrants.notifyRegistrants();
            }
            break;
    }
    if (error != RadioError.NONE) {
        switch (rr.mRequest) {
            case RIL_REQUEST_ENTER_SIM_PIN:
            case RIL_REQUEST_ENTER_SIM_PIN2:
            case RIL_REQUEST_CHANGE_SIM_PIN:
            case RIL_REQUEST_CHANGE_SIM_PIN2:
            case RIL_REQUEST_SET_FACILITY_LOCK:
                if (mIccStatusChangedRegistrants != null) {
                    if (RILJ_LOGD) {
                        riljLog("ON some errors fakeSimStatusChanged: reg count="
                                + mIccStatusChangedRegistrants.size());
                    }
                    mIccStatusChangedRegistrants.notifyRegistrants();
                }
                break;
        }
    }
  ...
}
```

#### registerForAvailable

```java
public void registerForAvailable(Handler h, int what, Object obj) {
    Registrant r = new Registrant (h, what, obj);
    synchronized (mStateMonitor) {
        mAvailRegistrants.add(r);
        if (mState.isAvailable()) {
            r.notifyRegistrant(new AsyncResult(null, null, null));
        }
    }
}
```

1、当设置Radio状态跟之前状态不同时触发

```java
protected void setRadioState(RadioState newState) {
    RadioState oldState;
	
		...

        if (mState.isAvailable() && !oldState.isAvailable()) {
            mAvailRegistrants.notifyRegistrants();
        }

        if (!mState.isAvailable() && oldState.isAvailable()) {
            mNotAvailRegistrants.notifyRegistrants();
        }
        ...
    }
}
```

#### registerForNotAvailable

```java
public void registerForNotAvailable(Handler h, int what, Object obj) {
    Registrant r = new Registrant (h, what, obj);

    synchronized (mStateMonitor) {
        mNotAvailRegistrants.add(r);

        if (!mState.isAvailable()) {
            r.notifyRegistrant(new AsyncResult(null, null, null));
        }
    }
}
```

1、和registerForAvailable监听器一样也是在设置Radio状态跟之前不同时触发。

#### registerForIccRefresh

```java
public void registerForIccRefresh(Handler h, int what, Object obj) {
    Registrant r = new Registrant (h, what, obj);
    mIccRefreshRegistrants.add(r);
}
```

1、当modem上报sim卡refresh时触发

```java
public void simRefresh(int indicationType, SimRefreshResult refreshResult) {
    ...
	
    if (RIL.RILJ_LOGD) mRil.unsljLogRet(RIL_UNSOL_SIM_REFRESH, response);
    mRil.mIccRefreshRegistrants.notifyRegistrants(new AsyncResult (null, response, null));
}
```

### UiccController对监听事件的处理

UiccController注册了4个监听器，但是只使用了3个Message消息，其中前两个使用了相同的Message。通过在开机LOG中搜索下面的LOG，我们可以确认，开机之后首先触发的是registerForAvailable监听器。

```
UNSOL_RESPONSE_SIM_STATUS_CHANGED|UNSOL_RESPONSE_RADIO_STATE_CHANGED|UNSOL_SIM_REFRESH
```

`EVENT_ICC_STATUS_CHANGED`的处理内容很简单，就是去主动获取sim卡的状态。然后接下来的流程就和初始化流程相对应，依次去初始化其它相关的类。

```java
switch (msg.what) {
    case EVENT_ICC_STATUS_CHANGED:
        if (DBG) log("Received EVENT_ICC_STATUS_CHANGED, calling getIccCardStatus");
        mCis[index].getIccCardStatus(obtainMessage(EVENT_GET_ICC_STATUS_DONE, index));
        break;
```

## UiccCard

### UiccCard功能

- 创建UiccCardApplication和CatService对象
- 提供访问UiccCardApplication对象的接口
- 提供sim卡移除的监听器
- 提供运营商规则状态接口
- 提供运营商规则改变监听器

### UiccCard更新机制

`UiccCard`更新是依赖于`UiccController` 的，当`UiccController`中的监听器监听到事件改变时，和开机初始化一样，会主动去获取sim卡状态，然后进行更新`UiccCard`。

## UiccCardApplication

### UiccCardApplication作用

- 创建并提供`IccRecords`、`IccFileHandler`对象
- 提供当前`UiccCardApplication`的状态、类型等信息
- 提供3个监听器，分别用于监听pin锁、网络锁和sim卡状态是否就绪

### UiccCardApplication更新机制

- `UiccCardApplication`更新机制和`UiccCard`类似，在`UiccCard`更新时，调用U`iccCardApplication`更新方法进行更新。
- `UiccCardApplication`注册监听了Radio unavailable事件，当接收到这个事件之后更改sim卡状态为unknown。

## IccFileHandler

`IccFileHandler`根据不同类型的sim卡有5个子类，目前市场上占有量最大的是USIM。`UiccCardApplication`根据卡的类型会创建`IccFileHandler`相应的子类。

### IccFileHandler功能

IccFileHandler主要提供访问sim卡中EF文件的一些接口。

## IccRecords

`IccRecords`也有3个子类，和`IccFileHandler`类似，`UiccCardApplication`也根据不同sim卡的类型创建不同的`IccRecords`的子类。

### IccRecords作用

- 提供sim卡相关信息的查询，如IMSI、ICCID等
- 提供了5个sim卡相关的监听器

### IccRecords更新机制

这里以`IccRecords`的子类`SIMRecords`为例进行介绍。

```java
mParentApp.registerForReady(this, EVENT_APP_READY, null);
mParentApp.registerForLocked(this, EVENT_APP_LOCKED, null);
if (DBG) log("SIMRecords X ctor this=" + this);

IntentFilter intentfilter = new IntentFilter();
intentfilter.addAction(CarrierConfigManager.ACTION_CARRIER_CONFIG_CHANGED);
```

`SIMRecords`初始化时注册了两个监听器和一个广播，比较常见的是第一个监听器，这个就是`UiccCardApplication`中定义的监听器。

```java
@UiccCardApplication.java
public void registerForReady(Handler h, int what, Object obj) {
    synchronized (mLock) {
        Registrant r = new Registrant (h, what, obj);
        mReadyRegistrants.add(r);
        notifyReadyRegistrantsIfNeeded(r);
    }
}
```

从这里可以看到注册监听器之后，马上回去判断是否通知。根据前面的流程可以判断，这里是满足条件的，所以接下来就是在`handleMessage`中进行处理。

```java
protected void fetchSimRecords() {
    mRecordsRequested = true;

    if (DBG) log("fetchSimRecords " + mRecordsToLoad);

    mCi.getIMSIForApp(mParentApp.getAid(), obtainMessage(EVENT_GET_IMSI_DONE));
    mRecordsToLoad++;

    mFh.loadEFTransparent(EF_ICCID, obtainMessage(EVENT_GET_ICCID_DONE));
    mRecordsToLoad++;

    ...
    loadEfLiAndEfPl();
    mFh.getEFLinearRecordSize(EF_SMS, obtainMessage(EVENT_GET_SMS_RECORD_SIZE_DONE));

    if (DBG) log("fetchSimRecords " + mRecordsToLoad + " requested: " + mRecordsRequested);
}
```

- SIMRecords的更新过程就是使用IccFileHandler将一些sim卡信息读取并保存起来。
- 当所有信息读取完之后，调用`onAllRecordsLoaded`方法，把sim卡的一些信息保存到数据库中





