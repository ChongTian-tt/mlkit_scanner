/*
 * HarmonyOS port of the Android ScannerOverlay view.
 * Draws a semi-transparent mask over the camera preview with a cutout for the
 * scan area, and renders rounded L-shaped corner borders that change color
 * based on whether scanning is active (green) or inactive (grey).
 */

import { CropRect } from './PluginConstants';
import { common2D, drawing } from '@kit.ArkGraphics2D';

@Component
export struct ScannerOverlay {
  private context: DrawingRenderingContext = new DrawingRenderingContext();
  @Prop @Watch('onPropChange') cropRect: CropRect | null = null;
  @Prop @Watch('onPropChange') isActive: boolean = false;
  private isCanvasReady: boolean = false;

  onPropChange() {
    if (this.isCanvasReady) {
      this.context.invalidate();
    }
  }

  /**
   * Build the mask path: full-screen rect minus rounded crop rect cutout.
   * Uses path boolean DIFFERENCE operation.
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

    // full screen rectangle
    path.addRect({ left: 0, top: 0, right: w, bottom: h });

    // rounded rect hole for the crop area (radius/2 matches the arc corner rounding)
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
   * Build the corner border path: four L-shaped corners with rounded arcs.
   * Each corner consists of moveTo → arcTo → lineTo, matching Android logic.
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

    // Top Left Corner: left arm → arc(180°,90°) → top arm
    path.moveTo(x, y + cornerLen);
    path.arcTo(x, y, x + radius, y + radius, 180, 90);
    path.lineTo(x + cornerLen, y);

    // Top Right Corner: top arm → arc(270°,90°) → right arm
    path.moveTo(x + cropWidth - cornerLen, y);
    path.arcTo(x + cropWidth - radius, y, x + cropWidth, y + radius, 270, 90);
    path.lineTo(x + cropWidth, y + cornerLen);

    // Bottom Right Corner: right arm → arc(0°,90°) → bottom arm
    path.moveTo(x + cropWidth, y + cropHeight - cornerLen);
    path.arcTo(x + cropWidth - radius, y + cropHeight - radius, x + cropWidth, y + cropHeight, 0, 90);
    path.lineTo(x + cropWidth - cornerLen, y + cropHeight);

    // Bottom Left Corner: bottom arm → arc(90°,90°) → left arm
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

    // 1. Draw semi-transparent background mask
    const bgBrush = new drawing.Brush();
    const blackColor: common2D.Color = { alpha: 120, red: 0, green: 0, blue: 0 };
    bgBrush.setColor(blackColor);
    canvas.attachBrush(bgBrush);
    canvas.drawPath(this.buildMaskPath(w, h));
    canvas.detachBrush();

    // 2. Draw corner borders
    if (this.cropRect) {
      const pen = new drawing.Pen();
      pen.setStrokeWidth(6);
      pen.setAntiAlias(true);
      pen.setCapStyle(drawing.CapStyle.ROUND_CAP);
      const borderColor: common2D.Color = this.isActive
        ? { alpha: 255, red: 0x43, green: 0xA0, blue: 0x47 }   // #43A047 green
        : { alpha: 255, red: 0x61, green: 0x61, blue: 0x61 };   // #616161 grey
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
      .hitTestBehavior(HitTestMode.Transparent)
      .onReady(() => {
        this.isCanvasReady = true;
        this.onDraw();
      })
  }
}
