/*
 * Copyright (c) 2026 SwanLink (Jiangsu) Technology Development Co., LTD.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { Log } from "@ohos/flutter_ohos";
import { getCurrentMLKitScannerView, MLKitScannerView } from "./MLKitScannerView";
import { PermissionsUtil } from "./PermissionsUtil";
import { CropRect, PluginConstants, PluginError } from "./PluginConstants";
import { ScannerOverlay } from "./ScannerOverlay";
import { common } from "@kit.AbilityKit";
import { customScan, scanBarcode, scanCore } from "@kit.ScanKit";
import { display } from "@kit.ArkUI";
import { window } from '@kit.ArkUI';

const TAG: string = "MlkitScannerPlugin_CameraPreviewComponent";

let currentCameraPreview: CameraPreviewComponent | null = null;

@Component
export struct CameraPreviewComponent {
  private mXComponentController: XComponentController = new XComponentController();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  @Prop flutterMLKitScannerView: MLKitScannerView | null = null;
  @State hasPermission: boolean = false;
  @State surfaceId: string = "";
  // width/height for the surface component – OHOS API only accepts numbers
  @State cameraWidth: number = 100; // full‑screen dims (required by XComponent)
  @State cameraHeight: number = 100;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  // actual screen dimensions (pixel to vp) for overlay calculations
  @State screenWidth: number = 0;
  @State screenHeight: number = 0;
  // crop rect state passed to overlay
  @State cropRectState: CropRect | null = null;
  // whether scanner is active (changes overlay border color)
  @State isActive: boolean = false;
  private window = this.context.windowStage.getMainWindowSync();

  build() {
      Stack() {
        // camera surface
        if (this.flutterMLKitScannerView && this.hasPermission) {
          XComponent({
            id: "componentId",
            type: XComponentType.SURFACE,
            controller: this.mXComponentController,
          })
            .onLoad(() => {
              Log.i(TAG, "XComponent onLoad");
              const scannerView = getCurrentMLKitScannerView();
              if (scannerView) {
                this.surfaceId = this.mXComponentController.getXComponentSurfaceId();
                scannerView.setSurfaceId(this.surfaceId);
                Log.i(TAG, `XComponent onLoad successs ${this.surfaceId}`);
                const options: scanBarcode.ScanOptions = {
                  scanTypes: [scanCore.ScanType.ALL],
                  enableMultiMode: false,
                  enableAlbum: false,
                };

                const viewControl: customScan.ViewControl = {
                  width: this.cameraWidth,
                  height: this.cameraHeight,
                  surfaceId: this.surfaceId
                };
                customScan.init(options);
                customScan.start(viewControl);
              }
            })
            .width(this.cameraWidth)
            .height(this.cameraHeight)
            .position({
              x: this.offsetX,
              y: this.offsetY,
            });
        }
        // scanner overlay on top of camera
        if (this.cropRectState) {
          ScannerOverlay({
            cropRect: this.cropRectState,
            isActive: this.isActive,
          })
        }
      }
      .alignContent(Alignment.Bottom)
      .width(PluginConstants.SCAN_COMPONENT_WIDTH_100)
      .height(PluginConstants.SCAN_COMPONENT_WIDTH_100)
  }

  private async refreshPermissionState(scene: string): Promise<boolean> {
    const scannerView = getCurrentMLKitScannerView();
    this.hasPermission = await PermissionsUtil.checkAndRequestCameraPermission(this.context);
    if (scannerView) {
      scannerView.userGrant = this.hasPermission;
    }
    Log.i(TAG, `${scene} permission result: ${this.hasPermission}`);
    return this.hasPermission;
  }

  async aboutToAppear(): Promise<void> {
    // keep reference for outside updates
    currentCameraPreview = this;
    const scannerView = getCurrentMLKitScannerView();

    Log.i(TAG, "aboutToAppear, cached userGrant=" + this.flutterMLKitScannerView?.userGrant);
    if (scannerView && scannerView.methodResult) {
      const initialCropRect = scannerView.initialScannerParameters?.initialCropRect;
      if (initialCropRect) {
        this.applyCropRect(initialCropRect);
      }

      if (!await this.refreshPermissionState('aboutToAppear')) {
        scannerView.methodResult.error(PluginError.AuthorizationCameraError, 'Camera permission denied', null);
        return;
      }

      try {
        this.registerWindow();

        Log.i(TAG, 'customScan.init success');
        scannerView.setCameraInitialized(true);
        scannerView.methodResult.success(true);
      } catch (error) {
        Log.e(TAG, "aboutToAppear customScan error: " + error);
        scannerView.methodResult.error(PluginError.InitCameraError, 'customScan.init failed', JSON.stringify(error));
      }
    }

  }

  // 窗口监听
  registerWindow() {
    try {
      const callback = async (windowEventType: window.WindowEventType) => {
        const scannerView = getCurrentMLKitScannerView();
        if (windowEventType === 1 && scannerView) {
          const hasPermission = await this.refreshPermissionState('windowEvent');
          if (!hasPermission) {
            this.isActive = false;
            return;
          }
          if (scannerView.isScan && scannerView.methodResult) {
            scannerView.resumeCamera(scannerView.methodResult)
          }
        }
      }
      this.window.on('windowEvent',callback);
    } catch (error) {
      Log.e(TAG, `Failed to unregister window focus listener: ${error}`);
    }
  }

  // 移除窗口监听
  unRegisterWindow() {
    this.window.off('windowEvent')
  }

  aboutToDisappear() {
    Log.i(TAG, "aboutToDisappear");
    currentCameraPreview = null;
    this.unRegisterWindow();
  }

  getSurfaceId(): string {
    return this.surfaceId;
  }

  setScanActive(active: boolean): void {
    this.isActive = active;
  }

  // helper for external calls (e.g. setCropArea)
  applyCropRect(rect: CropRect) {
    // screen size may already be stored; if not, compute now
    try {
      if (this.screenWidth === 0 || this.screenHeight === 0) {
        this.screenWidth = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
        this.screenHeight = this.getUIContext().px2vp(display.getDefaultDisplaySync().height);
      }
      this.cameraWidth = this.screenWidth;
      this.cameraHeight = this.screenHeight;
      this.offsetX = (this.screenWidth / 2) * (1 + rect.offsetX) - this.cameraWidth / 2;
      this.offsetY = (this.screenHeight / 2) * (1 + rect.offsetY) - this.cameraHeight / 2;
      this.cropRectState = rect;
    } catch (error) {
      Log.e(TAG, "applyCropRect error: " + error);
    }
  }
}

// export accessor for view class
export function getCurrentCameraPreview(): CameraPreviewComponent | null {
  return currentCameraPreview;
}
