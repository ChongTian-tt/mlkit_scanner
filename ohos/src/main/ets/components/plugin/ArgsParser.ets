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

import { Log } from '@ohos/flutter_ohos';
import { Size } from './PluginConstants';

const TAG: string = '[ArgsParser]:';

/**
 * 参数解析工具类
 * 提供静态方法将 Flutter 传入的 Object/Map 参数转换为强类型 Record，
 * 以及从参数中提取和校验特定类型的值
 */
export class ArgsParser {
  /**
   * 归一化参数，将框架传入的 Object 转换为强类型 Record
   * 支持 Map 和普通 Object 两种输入格式，递归处理嵌套结构
   * @param rawArgs - 原始参数对象
   * @returns 归一化后的键值对
   */
  static normalizeArgs(rawArgs: Object): Record<string, Object> {
    try {
      if (!rawArgs || typeof rawArgs !== 'object') {
        return {};
      }

      if (typeof (rawArgs as Record<string, Object>)['forEach'] === 'function') {
        const args: Record<string, Object> = {};
        const rawMap = rawArgs as Map<string, Object>;
        rawMap.forEach((value: Object, key: string) => {
          args[key] = ArgsParser.recursivelyConvertMap(value);
        });
        return args;
      }

      return ArgsParser.recursivelyConvertMap(rawArgs) as Record<string, Object>;
    } catch (error) {
      Log.w(TAG, 'normalizeArgs skipped: ' + JSON.stringify(error));
      return {};
    }
  }

  /**
   * 递归转换映射，将 Map 或嵌套对象转换为 Record<string, Object>
   * 处理三种类型：数组（递归每个元素）、Map（通过 forEach 遍历）、普通 Object（通过 Object.keys 遍历）
   * @param obj - 待转换的对象
   * @returns 转换后的对象
   */
  static recursivelyConvertMap(obj: Object): Object {
    if (obj === null || typeof obj !== 'object') {
      return obj;
    }

    // 先检查是否是数组(数组也有 forEach 方法,必须先判断)
    if (Array.isArray(obj)) {
      const result: Object[] = [];
      for (let i = 0; i < obj.length; i++) {
        result.push(ArgsParser.recursivelyConvertMap(obj[i]));
      }
      return result;
    }

    // 检查是否是 Map 对象(有 forEach 方法但不是数组)
    // Map 对象需要通过 forEach 遍历，Object.keys() 无法枚举 Map 的键
    const objRecord = obj as Record<string, Object>;
    if (typeof objRecord['forEach'] === 'function') {
      const converted: Record<string, Object> = {};
      const objMap = obj as Map<string, Object>;
      objMap.forEach((value: Object, key: string) => {
        converted[key] = ArgsParser.recursivelyConvertMap(value);
      });
      return converted;
    }

    // 如果是普通对象
    const converted: Record<string, Object> = {};
    const keys = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      converted[key] = ArgsParser.recursivelyConvertMap(objRecord[key]);
    }
    return converted;
  }

  /**
   * 解析正数尺寸参数
   * @param args - 包含 width 和 height 字段的键值对
   * @returns 有效的正数尺寸，参数无效时返回 null
   */
  static parsePositiveSize(args: Record<string, Object>): Size | null {
    const width = Number(args['width']);
    const height = Number(args['height']);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return null;
    }
    return { width: Math.round(width), height: Math.round(height) };
  }

  /**
   * 解析缩放值参数
   * @param args - 缩放参数
   * @returns 有效的缩放数值，无效时返回 null
   */
  static parseZoomValue(args: Object): number | null {
    if (args === null || args === undefined) {
      return null;
    }
    const num = Number(args);
    if (Number.isFinite(num)) {
      return num;
    }
    return null;
  }
}
