## 1.0.0

- Initial version, created by Stagehand

||||
|--- |--- |--- |
|MUTATION               |APPLIED TO         |RESULTS IN|
|SetMutation            |Document(v3)       |Document(v3)|
|SetMutation            |NoDocument(v3)     |Document(v0)|
|SetMutation            |null               |Document(v0)|
|PatchMutation          |Document(v3)       |Document(v3)|
|PatchMutation          |NoDocument(v3)     |NoDocument(v3)|
|PatchMutation          |null               |null|
|TransformMutation      |Document(v3)       |Document(v3)|
|TransformMutation      |NoDocument(v3)     |NoDocument(v3)|
|TransformMutation      |null               |null|
|DeleteMutation         |Document(v3)       |NoDocument(v0)|
|DeleteMutation         |NoDocument(v3)     |NoDocument(v0)|
|DeleteMutation         |null               |NoDocument(v0)|
