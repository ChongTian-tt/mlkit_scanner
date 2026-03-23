/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  bundleManager,
  abilityAccessCtrl,
  PermissionRequestResult,
  Permissions,
  Context
} from '@kit.AbilityKit';
import { Log } from '@ohos/flutter_ohos';

const TAG = '[PermissionsUtil] :';

export class PermissionsUtil {
  public static async checkAccessToken(permission: Permissions): Promise<abilityAccessCtrl.GrantStatus> {
    let atManager = abilityAccessCtrl.createAtManager();
    let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;
    let tokenId: number = 0;
    try {
      let bundleInfo: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
      tokenId = appInfo.accessTokenId;
    } catch (error) {
      Log.e(TAG, 'Failed to get bundle info for self. error: %{public}s',
        JSON.stringify(error));
    }
    try {
      grantStatus = await atManager.checkAccessToken(tokenId, permission);
    } catch (error) {
      Log.e(TAG, 'Failed to check access token. error: %{public}s' + JSON.stringify(error));
    }
    return grantStatus;
  }

  public static async reqPermissionsFromUser(context: Context, permission: Permissions): Promise<number[]> {
    let atManager = abilityAccessCtrl.createAtManager();
    let grantStatus: PermissionRequestResult = { permissions: [], authResults: [] }
    try {
      grantStatus = await atManager.requestPermissionsFromUser(context, [permission]);
    } catch (error) {
      Log.e(TAG, 'Failed to check access token. error: %{public}s', JSON.stringify(error));
    }
    return grantStatus.authResults;
  }

  // 申请权限
  public static async requestCameraPermission(context: Context, permission: Permissions): Promise<boolean> {
    let valid = false;
    let grantStatus = await PermissionsUtil.reqPermissionsFromUser(context, permission);
    let length: number = grantStatus.length;
    for (let i = 0; i < length; i++) {
      if (grantStatus[i] === 0) {
        valid = true;
      } else {
        return await PermissionsUtil.re_authentication(context, permission);
      }
    }
    return valid;
  }


  // 检查权限 初始化相机 开始扫描
  public static async checkAndRequestCameraPermission(context: Context, permission: Permissions): Promise<boolean> {

    let valid = false;
    let grantStatus = await PermissionsUtil.checkAccessToken(permission);
    if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
      valid = true;
    } else {
      valid = await PermissionsUtil.requestCameraPermission(context, permission);
    }
    return valid;
  }

  public static async re_authentication(context: Context, permission: Permissions): Promise<boolean> {
    let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    try {
      let data: Array<abilityAccessCtrl.GrantStatus> =
        await atManager.requestPermissionOnSetting(context, [permission]);
      if (data[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      } else {
        return false;
      }
    } catch (error) {
      Log.e(TAG, 'checkAndRequestCameraPermission grantStatus ');
      return false;
    }
  }
}