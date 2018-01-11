---
title: "Telephony之subscription介绍"
layout: page
date: 2018-01-09 14:14
---

[TOC]

## sim卡初始化流程

![](/wiki/static/images/sim_card_init.png)

整体流程是在`SIMRecords`加载完所有的文件之后，通知`IccCardProxy`把sim卡相关的信息更新到数据库（telephony.db）中，并且完成slotid、subid、phoneid的映射。

> telephony.db   data/user_de/0/com.android.providers.telephony/databases  

## SubscriptionInfoUpdater

### 初始化

```java
@PhoneFactory.java
sSubInfoRecordUpdater = telephonyComponentFactory.makeSubscriptionInfoUpdater(
        BackgroundThread.get().getLooper(), context, sPhones, sCommandsInterfaces);
```

- Phone进程初始化时在`PhoneFactory`中创建。

```java
public SubscriptionInfoUpdater(
        Looper looper, Context context, Phone[] phone, CommandsInterface[] ci) {
    super(looper);
    ...
    IntentFilter intentFilter = new IntentFilter(TelephonyIntents.ACTION_SIM_STATE_CHANGED);
    intentFilter.addAction(IccCardProxy.ACTION_INTERNAL_SIM_STATE_CHANGED);
    mContext.registerReceiver(sReceiver, intentFilter);
}
```

- 构造函数中主要是注册了一个广播监听器，接收`IccCardProxy`发来的广播。
- 这里只创建了一个`SubscriptionInfoUpdater`对象，根据phoneId进行区分具体是哪一张卡。

### 添加到数据库

如果手机插入了两张卡，会等两张卡都加载完之后，才回去添加到数据库。

```java
@SubscriptionInfoUpdater.java
synchronized protected void updateSubscriptionInfoByIccId() {
	...
    ContentResolver contentResolver = mContext.getContentResolver();
    String[] oldIccId = new String[PROJECT_SIM_NUM];
    for (int i = 0; i < PROJECT_SIM_NUM; i++) {
        oldIccId[i] = null;
        List<SubscriptionInfo> oldSubInfo =
                SubscriptionController.getInstance().getSubInfoUsingSlotIndexWithCheck(i, false,
                mContext.getOpPackageName());
        if (oldSubInfo != null && oldSubInfo.size() > 0) {
            oldIccId[i] = oldSubInfo.get(0).getIccId();
            logd("updateSubscriptionInfoByIccId: oldSubId = "
                    + oldSubInfo.get(0).getSubscriptionId());
            if (mInsertSimState[i] == SIM_NOT_CHANGE && !mIccId[i].equals(oldIccId[i])) {
                mInsertSimState[i] = SIM_CHANGED;
            }	
            if (mInsertSimState[i] != SIM_NOT_CHANGE) {
                ContentValues value = new ContentValues(1);
                value.put(SubscriptionManager.SIM_SLOT_INDEX,
                        SubscriptionManager.INVALID_SIM_SLOT_INDEX);
                contentResolver.update(SubscriptionManager.CONTENT_URI, value,
                        SubscriptionManager.UNIQUE_KEY_SUBSCRIPTION_ID + "="
                        + Integer.toString(oldSubInfo.get(0).getSubscriptionId()), null);

                // refresh Cached Active Subscription Info List
                SubscriptionController.getInstance().refreshCachedActiveSubscriptionInfoList();
            }
        } else {
            if (mInsertSimState[i] == SIM_NOT_CHANGE) {
                // no SIM inserted last time, but there is one SIM inserted now
                mInsertSimState[i] = SIM_CHANGED;
            }
            oldIccId[i] = ICCID_STRING_FOR_NO_SIM;
            logd("updateSubscriptionInfoByIccId: No SIM in slot " + i + " last time");
        }
    }
	...
    for (int i = 0; i < PROJECT_SIM_NUM; i++) {
        if (mInsertSimState[i] == SIM_NOT_INSERT) {
            logd("updateSubscriptionInfoByIccId: No SIM inserted in slot " + i + " this time");
        } else {
            if (mInsertSimState[i] > 0) {
                //some special SIMs may have the same IccIds, add suffix to distinguish them
                //FIXME: addSubInfoRecord can return an error.
                mSubscriptionManager.addSubscriptionInfoRecord(mIccId[i]
                        + Integer.toString(mInsertSimState[i]), i);
                logd("SUB" + (i + 1) + " has invalid IccId");
            } else /*if (sInsertSimState[i] != SIM_NOT_INSERT)*/ {
                mSubscriptionManager.addSubscriptionInfoRecord(mIccId[i], i);
            }
	}
}	
```

- 循环处理两张卡
- 首先根据`sim_id`字段查询数据库，看看是否已经存在了信息。
- 如果存在就更新数据库。
- 如果不存在就调用到`addSubscriptionInfoRecord`中进行处理。

接下来看针对slot_id不存在的卡处理，这种情况发生在之前数据库中没有信息，或者有一条信息，这次插入了两张卡的情况。也就说下面三种情况会到这里来：

- 之前没卡，这次插入1张卡。
- 之前没卡，这次插入2张卡。
- 之前有1张卡， 这次插入2张卡。

```java
@SubscriptionController.java
public int addSubInfoRecord(String iccId, int slotIndex) {
    try {
        if (iccId == null) {
            if (DBG) logdl("[addSubInfoRecord]- null iccId");
            return -1;
        }

        ContentResolver resolver = mContext.getContentResolver();
        Cursor cursor = resolver.query(SubscriptionManager.CONTENT_URI,
                new String[]{SubscriptionManager.UNIQUE_KEY_SUBSCRIPTION_ID,
                        SubscriptionManager.SIM_SLOT_INDEX, SubscriptionManager.NAME_SOURCE},
                SubscriptionManager.ICC_ID + "=?", new String[]{iccId}, null);

        boolean setDisplayName = false;
        try {
            if (cursor == null || !cursor.moveToFirst()) {
                setDisplayName = true;
                Uri uri = insertEmptySubInfoRecord(iccId, slotIndex);
                if (DBG) logdl("[addSubInfoRecord] New record created: " + uri);
            } else {
                ContentValues value = new ContentValues();

                if (slotIndex != oldSimInfoId) {
                    value.put(SubscriptionManager.SIM_SLOT_INDEX, slotIndex);
                }
                if (nameSource != SubscriptionManager.NAME_SOURCE_USER_INPUT) {
                    setDisplayName = true;
                }
                if (value.size() > 0) {
                    resolver.update(SubscriptionManager.CONTENT_URI, value,
                            SubscriptionManager.UNIQUE_KEY_SUBSCRIPTION_ID +
                                    "=" + Long.toString(subId), null);
                    refreshCachedActiveSubscriptionInfoList();
                }
            }
        }
        sPhones[slotIndex].updateDataConnectionTracker();
}
```

- 根据icc_id查询数据库，如果没有查询到就在数据库中插入一条新的记录，如果有相同信息，就进行更新。
- 把sim卡名称写入到数据库中，字段display_name
- 调用DcTracker.update()

接下来再返回到`updateSubscriptionInfoByIccId`，把手机号码加入到数据库，设置默认的数据卡。最后通知注册监听的客户端，并且发送广播`ACTION_SUBINFO_CONTENT_CHANGE`。

```java
SubscriptionController.getInstance().notifySubscriptionInfoChanged();
```

### 继续更新

再次回到`handleSimLoaded`方法中，接着进行处理。

- 设置`MccTable`的配置，比如语言、时区等
- 更新数据库中其他字段，比如手机号码、名字。
- 设置网络模式，gsm、cdma、tdscdma、wcdma、lte等
- 查询选网模式，自动或者手动，如果不是自动就设置成自动
- 更新com.android.phone_preferences.xml中subid
- 发送广播**Intent.ACTION_SIM_STATE_CHANGED**

## 总结

这篇主要介绍了SIMRecords中加载完sim卡信息之后，把信息更新到数据库的过程。主要涉及到SubscriptionInfoUpdater、SubscriptionController、SubscriptionManager。