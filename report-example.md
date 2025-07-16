
## Informationals

### [I-1] `PoolFactory::PoolFactory__PoolDoesNotExist` is not used and should be removed

```diff
- error PoolFactory__PoolDoesNotExist(address tokenAddress);
```

### [I-2] Lacking zero address checks

```diff
  constructor(address wethToken) {
+    if(wethToken == address(0)) {
+      revert();
+    }
    i_wethToken = wethToken;
  }
```