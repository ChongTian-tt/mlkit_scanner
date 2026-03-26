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

import { CropRect } from './PluginConstants';
import { common2D, drawing } from '@kit.ArkGraphics2D';

/**
 * 在相机预览上绘制一个半透明的遮罩，并为其留出一个剪切区域
 * 扫描区域，并渲染出会变色的圆角L形边框
 * 根据扫描是处于活动状态（绿色）还是非活动状态（灰色）来判断。
 */
@Component
export struct ScannerOverlay {
  private context: DrawingRenderingContext = new DrawingRenderingContext();
  @Prop @Watch('onPropChange') cropRect: CropRect | null = null;
  @Prop @Watch('onPropChange') isActive: boolean = false;
  private isCanvasReady: boolean = false;

  onPropChange() {
    if (this.isCanvasReady) {
      this.context.invalidate();
      this.onDraw();
    }
  }

  /**
   * 构建遮罩路径：全屏矩形减去圆角裁剪矩形剪切。
   * 使用路径布尔差集操作。
   */
  private buildMaskPath(w: number, h: number): drawing.Path {
    const path = new drawing.Path();
    if (this.cropRect == null) {
      return path;
    }
    const rect = this.cropRect;
    const cropWidth = w * rect.scaleWidth;
    const cropHeight = h * rect.scaleHeight;
    const x = w / 2 * (1 + rect.offsetX) - cropWidth / 2;
    const y = h / 2 * (1 + rect.offsetY) - cropHeight / 2;
    const cornerLen = cropWidth * 0.05;
    const radius = cornerLen / 2;

    // 全屏矩形
    path.addRect({
      left: 0,
      top: 0,
      right: w,
      bottom: h
    });

    // 裁剪区域的圆角矩形孔（半径/2与圆角弧度相匹配）
    const hole = new drawing.Path();
    const cropRectDef: common2D.Rect = {
      left: x,
      top: y,
      right: x + cropWidth,
      bottom: y + cropHeight
    };
    const roundRect = new drawing.RoundRect(cropRectDef, radius / 2, radius / 2);
    hole.addRoundRect(roundRect, drawing.PathDirection.CLOCKWISE);

    path.op(hole, drawing.PathOp.DIFFERENCE);
    return path;
  }

  /**
   * 构建角落边界路径：四个带有圆弧的L形角落。
   * 每个角点都由moveTo → arcTo → lineTo组成
   */
  private buildCornerPath(w: number, h: number): drawing.Path {
    const path = new drawing.Path();
    if (this.cropRect == null) {
      return path;
    }
    const rect = this.cropRect;
    const cropWidth = w * rect.scaleWidth;
    const cropHeight = h * rect.scaleHeight;
    const x = w / 2 * (1 + rect.offsetX) - cropWidth / 2;
    const y = h / 2 * (1 + rect.offsetY) - cropHeight / 2;
    const cornerLen = cropWidth * 0.05;
    const radius = cornerLen / 2;

    // 左上角：左臂 → 弧形（180°，90°） → 上臂
    path.moveTo(x, y + cornerLen);
    path.arcTo(x, y, x + radius, y + radius, 180, 90);
    path.lineTo(x + cornerLen, y);

    // 右上角：上臂 → 弧形（270°，90°）→ 右臂
    path.moveTo(x + cropWidth - cornerLen, y);
    path.arcTo(x + cropWidth - radius, y, x + cropWidth, y + radius, 270, 90);
    path.lineTo(x + cropWidth, y + cornerLen);

    // 右下角：右臂 → 弧形（0°，90°）→ 下臂
    path.moveTo(x + cropWidth, y + cropHeight - cornerLen);
    path.arcTo(x + cropWidth - radius, y + cropHeight - radius, x + cropWidth, y + cropHeight, 0, 90);
    path.lineTo(x + cropWidth - cornerLen, y + cropHeight);

    // 左下角：下臂 → 弧形（90°，90°）→ 左臂
    path.moveTo(x + cornerLen, y + cropHeight);
    path.arcTo(x, y + cropHeight - radius, x + radius, y + cropHeight, 90, 90);
    path.lineTo(x, y + cropHeight - cornerLen);

    return path;
  }

  private onDraw() {
    const canvas = this.context.canvas;
    if (!canvas) {
      return;
    }
    const w = canvas.getWidth();
    const h = canvas.getHeight();

    canvas.clear({
      alpha: 0,
      red: 0,
      green: 0,
      blue: 0
    });

    // 1. 绘制半透明背景遮罩
    const bgBrush = new drawing.Brush();
    const blackColor: common2D.Color = {
      alpha: 120,
      red: 0,
      green: 0,
      blue: 0
    };
    bgBrush.setColor(blackColor);
    canvas.attachBrush(bgBrush);
    canvas.drawPath(this.buildMaskPath(w, h));
    canvas.detachBrush();

    // 2.绘制角落边框
    if (this.cropRect) {
      const pen = new drawing.Pen();
      pen.setStrokeWidth(6);
      pen.setAntiAlias(true);
      pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
      const borderColor: common2D.Color = this.isActive
        ? {
          alpha: 255,
          red: 0x43,
          green: 0xA0,
          blue: 0x47
        }   // #43A047 green
        : {
          alpha: 255,
          red: 0x61,
          green: 0x61,
          blue: 0x61
        }; // #616161 grey
      pen.setColor(borderColor);
      canvas.attachPen(pen);
      canvas.drawPath(this.buildCornerPath(w, h));
      canvas.detachPen();
    }
  }

  build() {
    Canvas(this.context)
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .hitTestBehavior(HitTestMode.Block)
      .onReady(() => {
        this.isCanvasReady = true;
        this.onDraw();
      })
      .onAreaChange(() => {
        if (this.isCanvasReady) {
          this.onDraw();
        }
      })
  }
}
