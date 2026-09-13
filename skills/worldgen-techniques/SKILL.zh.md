---
name: worldgen-techniques
description: Use when building 3D scenes/terrain from a reference image — proven techniques distilled from open-source worldgen projects
---

# Worldgen Techniques(开源项目技法摘要)

供参考取用的武器库,不是必须遵守的规程。核心流程仍是递归:整体→局部→再整体。

## 地形(参考 Infinigen / terrain-erosion-3-ways)

- **高度场分层叠加**:基底大势(低频)+ 山脊细节(ridged noise,`1-|noise|`)+
  domain warp(用另一张噪声扰动采样坐标,消除网格感)。逐层与参考剪影并排校。
- **地貌算子**:河谷=沿水线下切+
  两岸放坡;湖盆=局部压平+沿岸缓坡;山脊线=脊噪声沿走向拉伸。按参考逐条摆,
  不用全局随机。
- **侵蚀**:简化液压侵蚀几十~几百次迭代(水滴下坡搬运沉积)立刻去"塑料感";
  热侵蚀(坡度超阈值就坍)让岩壁碎裂自然。JS/Python 都能百行内实现。
- **崖壁贴图防拉伸**:陡面用 **triplanar**(按法线混合三向投影)或独立岩面
  材质;高度场直贴必然竖条纹拉伸(陡崖的通病)。
- **分界线**:雪线/岩草界用高度+坡度双阈值再加噪声扰动边缘,不许一刀切。

## 场景规格(先规划后建造)

先产出结构化规格再动手:regions(分区)/ terrain(地形要素)/ assets(资产
清单与数量)/ materials / spatial relations(邻接、朝向、依附)。

## 渲染精修(render-based refinement,与我们的眼审同构)

渲染→与参考并排→改参数→再渲染的闭环,每层都做;放大裁决(子视锥)优先。

## 可挖的开源库

- Infinigen(princeton):地形/植被/材质全程序化。
- dandrino/terrain-erosion-3-ways:侵蚀三法(模拟/ML/噪声)带 Python 源码。
- three.js 内置:PlaneGeometry 顶点位移即高度场;ShaderMaterial 做 triplanar。
