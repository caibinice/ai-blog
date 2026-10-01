---
title: Engineering a 3D Parking Twin for Desktop and Mobile
excerpt: A practical rebuild of a parking visualization covering asset reduction, consistent occupancy data, rendering lifecycle, optional WebGPU, touch controls, and reliable static deployment.
---

A parking visualization becomes useful when visitors can open the campus quickly, understand occupancy, and navigate to the relevant zone. Geometry, application state, input handling, and deployment need explicit boundaries.

This project uses Angular and Babylon.js. I rebuilt an existing hospital-campus dashboard as an anonymized, self-contained demonstration and added a dedicated lightweight mobile route.

[Desktop demo](/smartParking/) · [Mobile demo](/smartParking/mobile) · [GitHub source](https://github.com/caibinice/3dSmartParking)

![3D smart parking dashboard](/images/project-parking.png)

## Start with the asset budget

The original asset directory was approximately 616 MB. Three campus models together occupied about 479 MB; the default GLB alone contained 164,807,820 bytes. Large opening videos and duplicated dashboard components added loading and maintenance costs.

The rebuild upgrades Angular18 to21.2.25 and Babylon.js7 to9.29.0. It separates pure data functions, a signals store, a scene class, and presentation. Routes and the 3D engine are lazy-loaded. The production initial application chunk is229.59kB; rendering modules load separately.

The published campus model is7,089,576 bytes, approximately95.7% smaller than the previous default. The mobile route requests no campus GLB and builds a representative low-polygon site procedurally.

## Anonymization is an asset operation

Changing an HTML title does not change physical lettering inside a model. The original sign was geometry, while image textures could also contain identifying text. The conversion removes sign nodes, high-detail vehicles, image textures, animations, and the large distant plane. Nodes, meshes, and materials receive generic names. The original opening and monitoring videos and fixed monitoring addresses are excluded from the published repository.

The interface uses generic company and hospital names. A DynamicTexture supplies the generic hospital sign after loading. The original source assets remain in an external local backup.

glTF Transform provides a reproducible pipeline. Deduplication and welding precede simplification and pruning; a small error budget preserves the building silhouette.

```javascript
await document.transform(
  dedup(), weld(),
  simplify({ simplifier: MeshoptSimplifier, ratio: 0.15, error: 0.001 }),
  prune()
);
```

The final asset has no embedded image textures. It remains directly readable by the local glTF loader without a separate remote decoder. Precompressed gzip files reduce transfer cost at Nginx.

## One source of occupancy truth

Zone capacity and occupancy feed every metric, recommendation, record, and 3D ratio. Total capacity is300. A five-second simulation changes one vehicle at a time and keeps each zone between zero and capacity.

```typescript
const capacity = zones.reduce((sum, zone) => sum + zone.capacity, 0);
const occupied = zones.reduce((sum, zone) => sum + zone.occupied, 0);
const free = capacity - occupied;
```

Tests run3000 updates and check bounds and conservation. The visual slot count represents occupancy proportion rather than all300 individual real spaces; authoritative values remain in the panels.

The dashboard supports zone focus, overview and top-down views, camera orbit, alert acknowledgement, record filtering, CSV export, and a recommendation for the zone with the most free capacity. All records and alerts are explicitly simulated. No gate, camera, or billing system is connected.

## Separate rendering from business updates

ParkingScene owns the engine, camera, meshes, input listeners, and disposal. Angular runs without Zone.js; periodic business updates remain separate from scene.render. Slots and vehicles each share a thin-instance source mesh, and instance matrices change only when occupancy changes.

A ResizeObserver follows canvas dimensions. Hidden tabs pause rendering and simulation. Leaving the route clears the engine, scene, timers, observer, and touch listeners. Async model completion checks whether the scene has already been destroyed.

Default rendering uses WebGL. The query parameter`?renderer=webgpu` selects the optional WebGPU path, with capability detection and initialization before any scene resources. Unsupported initialization falls back to WebGL. A newer backend complements smaller assets and fewer repeated objects; it does not replace those optimizations.

Quality profiles cap devicePixelRatio, with automatic, high, balanced, and low-power options. Desktop rendering targets60fps and mobile30fps. Automatic mode reduces resolution when measured rendering performance is low. The displayed FPS counts rendered frames rather than animation callbacks. Browser tests are observations on the tested machine, not universal phone-performance claims.

## Mobile landscape and touch

The dedicated/mobile route uses simple building blocks and floor strips. It retains zone semantics and instance-based vehicles while reducing geometry. Primary controls have at least44px touch height.

A fullscreen gesture attempts system landscape locking. If the browser restricts that API, portrait orientation still receives a CSS-rotated landscape workspace. Input coordinates are inverse-transformed to match the rotated canvas:

```typescript
const point = portrait
  ? { x: event.clientY - rect.top, y: rect.right - event.clientX }
  : { x: event.clientX - rect.left, y: event.clientY - rect.top };
```

One finger rotates the camera; two-finger distance changes zoom. Camera pitch and distance are bounded. Zone buttons provide precise navigation without requiring delicate gestures.

## Delivery and verification

Angular's production base href matches/smartParking/. Nginx serves both the index and/mobile deep link, with missing models returning404 rather than blog HTML. Model failure activates the lightweight campus; engine failure exposes a retry action.

Static builds enter timestamped releases and an atomic symlink switch activates them. Nginx configuration is backed up and tested before reload; failure restores the previous configuration and release link. Fingerprinted JS/CSS use long caching, HTML revalidates, and models use shorter caching.

Type checking, data tests, texture/name audits, production builds, desktop interaction, landscape/portrait layouts, and zero mobile GLB requests form the validation loop. The blog adds the project card, an actual screenshot, and this article in all three languages.

## References

- [Angular compatibility](https://angular.dev/reference/versions)
- [Babylon.js instances](https://doc.babylonjs.com/features/featuresDeepDive/mesh/copies/instances)
- [Babylon.js scene optimization](https://doc.babylonjs.com/features/featuresDeepDive/scene/optimize_your_scene)
- [Babylon.js WebGPU](https://doc.babylonjs.com/setup/support/webGPU)
- [glTF Transform](https://gltf-transform.dev/)
- [Implementation and optimization record](https://github.com/caibinice/3dSmartParking/blob/main/docs/optimization-plan.md)
