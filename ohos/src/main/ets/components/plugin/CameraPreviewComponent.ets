/*
 * Copyright (c) 2026 SwanLink (Jiangsu) Technology Development Co., LTD.
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

import { display } from '@kit.ArkUI';
import { Log } from '@ohos/flutter_ohos';
import { common, AbilityLifecycleCallback } from '@kit.AbilityKit';
import { customScan, scanBarcode, scanCore } from '@kit.ScanKit';
import { PermissionsUtil } from './PermissionsUtil';
import { ScannerOverlay } from './ScannerOverlay';
import { getCurrentMLKitScannerView, MLKitScannerView } from './MLKitScannerView';
import { CropRect, PluginConstants, PluginError } from './PluginConstants';

const TAG: string = 'MlkitScannerPlugin_CameraPreviewComponent';

let currentCameraPreview: CameraPreviewComponent | null = null;

@Component
export struct CameraPreviewComponent {
  private mXComponentController: XComponentController = new XComponentController();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private isScanKitInitialized: boolean = false;
  private lifecycleId: number = -1;
  @Prop flutterMLKitScannerView: MLKitScannerView | null = null;
  @State hasPermission: boolean = false;
  @State surfaceId: string = '';
  // xComponent 宽度/高度——OHOS API仅接受number类型
  @State cameraWidth: number = 0;
  @State cameraHeight: number = 0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  // 裁剪矩形状态
  @State cropRectState: CropRect | null = null;
  //  扫描仪是否处于活动状态（改变覆盖边框颜色）
  @State isActive: boolean = false;

  build() {
    Stack() {
      if (this.flutterMLKitScannerView && this.hasPermission) {
        XComponent({
          id: 'componentId',
          type: XComponentType.SURFACE,
          controller: this.mXComponentController,
        })
          .onLoad(() => {
            this.onLoadHandle();
          })
          .width(this.cameraWidth)
          .height(this.cameraHeight)
          .backgroundColor(Color.White)
          .position({
            x: this.offsetX,
            y: this.offsetY,
          });
        // scanner overlay on top of camera
        if (this.cropRectState) {
          ScannerOverlay({
            cropRect: this.cropRectState,
            isActive: this.isActive,
          })
            .key(
              'scanner-overlay-' +
              this.cropRectState.scaleWidth + '-' +
              this.cropRectState.scaleHeight + '-' +
              this.cropRectState.offsetX + '-' +
              this.cropRectState.offsetY + '-' +
              this.isActive,
            )
        }
      }
    }
    .alignContent(Alignment.Bottom)
    .width(PluginConstants.SCAN_COMPONENT_WIDTH_100)
    .height(PluginConstants.SCAN_COMPONENT_WIDTH_100)
  }

  getSurfaceId(): string {
    return this.surfaceId;
  }

  setScanActive(active: boolean): void {
    this.isActive = active;
  }

  getScanActive(): boolean {
    return this.isActive;
  }

  private async onLoadHandle(): Promise<void> {
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (this.flutterMLKitScannerView) {
      this.surfaceId = this.mXComponentController.getXComponentSurfaceId();
      this.flutterMLKitScannerView.setSurfaceId(this.surfaceId);
      Log.i(TAG, `XComponent onLoad successs ${this.surfaceId}`);
      await this.tryInitScanKit('onLoad');
    }
  }

  async aboutToAppear(): Promise<void> {
    currentCameraPreview = this;
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();

    this.registerLifecycle();
    await this.onInitCameraPreviewRequested();
  }

  aboutToDisappear() {
    Log.i(TAG, 'aboutToDisappear');
    currentCameraPreview = null;
    this.isScanKitInitialized = false;
    this.unRegisterLifecycle();
  }

  private registerLifecycle() {
    if (this.lifecycleId >= 0) {
      return;
    }
    try {
      const callbacks: AbilityLifecycleCallback = {
        onAbilityCreate: () => {
        },
        onWindowStageCreate: () => {
        },
        onWindowStageActive: () => {
        },
        onWindowStageInactive: () => {
        },
        onWindowStageDestroy: () => {
        },
        onAbilityDestroy: () => {
        },
        onAbilityContinue: () => {
        },
        onAbilityForeground: async () => {
          // 解锁或回到前台时，恢复扫描
          await this.refreshPermissionState('abilityForeground');
          if (!this.hasPermission) {
            this.isActive = false;
            return;
          }
          await getCurrentMLKitScannerView()?.onHostForeground();
        },
        onAbilityBackground: async () => {
          // 锁屏或退到后台时，暂停扫描
          await getCurrentMLKitScannerView()?.onHostBackground();
        },
      };
      this.lifecycleId = this.context.getApplicationContext().on('abilityLifecycle', callbacks as ESObject);
    } catch (error) {
      Log.e(TAG, `Failed to register lifecycle listener: ${error}`);
    }
  }

  private unRegisterLifecycle() {
    if (this.lifecycleId < 0) {
      return;
    }
    try {
      this.context.getApplicationContext().off('abilityLifecycle', this.lifecycleId);
    } catch (error) {
      Log.e(TAG, `Failed to unregister lifecycle listener: ${error}`);
    }
    this.lifecycleId = -1;
  }

  private async refreshPermissionState(scene: string): Promise<void> {
    this.hasPermission = await PermissionsUtil.checkAndRequestCameraPermission(this.context);
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (this.flutterMLKitScannerView) {
      this.flutterMLKitScannerView.userGrant = this.hasPermission;
    }
    Log.i(TAG, `${scene} permission result: ${this.hasPermission}`);
  }

  async onInitCameraPreviewRequested(): Promise<void> {
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (!this.flutterMLKitScannerView || !this.flutterMLKitScannerView.methodResult) {
      return;
    }

    await this.refreshPermissionState('initCameraPreview');
    this.applyCropRect();
    if (!this.hasPermission) {
      this.flutterMLKitScannerView.methodResult.error(
        PluginError.AuthorizationCameraError,
        'Camera permission denied',
        null,
      );
      this.flutterMLKitScannerView.methodResult = null;
      return;
    }

    await this.tryInitScanKit('initCameraPreview');
  }

  private async tryInitScanKit(scene: string): Promise<void> {
    this.flutterMLKitScannerView = getCurrentMLKitScannerView();
    if (!this.flutterMLKitScannerView || !this.flutterMLKitScannerView.methodResult ||
      !this.surfaceId || !this.hasPermission) {
      return;
    }

    if (this.isScanKitInitialized || this.flutterMLKitScannerView.isCameraInitialized) {
      this.flutterMLKitScannerView.methodResult.success(true);
      this.flutterMLKitScannerView.methodResult = null;
      return;
    }

    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: false,
      enableAlbum: false,
    };

    try {
      customScan.init(options);
      this.isScanKitInitialized = true;
      this.flutterMLKitScannerView.setCameraInitialized(true);
      this.flutterMLKitScannerView.methodResult.success(true);
      Log.i(TAG, `${scene} customScan.init success`);
    } catch (error) {
      Log.e(TAG, `${scene} customScan init error: ` + error);
      this.flutterMLKitScannerView.methodResult?.error(
        PluginError.InitCameraError,
        'customScan.init failed',
        JSON.stringify(error),
      );
    }
  }

  applyCropRect() {
    try {
      if (!this.flutterMLKitScannerView || !this.flutterMLKitScannerView.initialScannerParameters ||
        !this.flutterMLKitScannerView.initialScannerParameters.initialCropRect) {
        return;
      }
      const initialCropRect = this.flutterMLKitScannerView.initialScannerParameters.initialCropRect;
      if (this.cameraWidth === 0 || this.cameraHeight === 0) {
        this.cameraWidth = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
        this.cameraHeight = this.getUIContext().px2vp(display.getDefaultDisplaySync().height);
      }
      this.offsetX = (this.cameraWidth / 2) * (1 + initialCropRect.offsetX) - this.cameraWidth / 2;
      this.offsetY = (this.cameraHeight / 2) * (1 + initialCropRect.offsetY) - this.cameraHeight / 2;
      this.cropRectState = {
        scaleWidth: initialCropRect.scaleWidth,
        scaleHeight: initialCropRect.scaleHeight,
        offsetX: initialCropRect.offsetX,
        offsetY: initialCropRect.offsetY,
      };
    } catch (error) {
      Log.e(TAG, 'applyCropRect error: ' + error);
    }
  }
}

export function getCurrentCameraPreviewComponent(): CameraPreviewComponent | null {
  return currentCameraPreview;
}
