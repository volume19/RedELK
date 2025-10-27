# RedELK Versioning Scheme

## Semantic Versioning

RedELK follows [Semantic Versioning](https://semver.org/) with the format `MAJOR.MINOR.PATCH`:

### Version Format: MAJOR.MINOR.PATCH

- **MAJOR** version: Incompatible API changes or major architectural changes
  - Example: RedELK 2.x → 3.x (Elastic Stack 7.x → 8.x upgrade)
  - Breaking changes that require manual migration
  - New deployment requirements (e.g., OS version, Docker version)

- **MINOR** version: New features added in a backwards-compatible manner
  - New C2 framework support (e.g., adding Sliver, Havoc)
  - New dashboard features
  - New alert types
  - Enhanced data processing capabilities
  - No breaking changes to existing deployments

- **PATCH** version: Backwards-compatible bug fixes and improvements
  - Bug fixes (authentication, healthchecks, timing issues)
  - Documentation updates
  - Configuration improvements
  - Performance optimizations
  - No new features, no breaking changes

## Version History

### v3.0.x Series - Elastic Stack 8.15.3

#### v3.0.4 (2025-10-27)
**COMPLETE FIX: Universal Parsing + Redirector Support**

Final comprehensive fix combining all lessons learned:
- Supports BOTH nested and flat field structures
- Auto-detects log type from file path when field missing
- Complete Cobalt Strike parsing (beacon, events, weblog, etc.)
- Redirector parsing (Apache, Nginx, HAProxy) with ECS fields
- Works with ANY Filebeat configuration
- No manual fixes needed - works out of the box

**Git Tag**: `v3.0.4`
**Commit**: TBD

#### v3.0.3 (2025-10-26)
**ROOT CAUSE FIX: Deployment Script Includes Parsing**

Deployment script now embeds complete Cobalt Strike parsing in main.conf:
- Previous versions created main.conf with ONLY routing (no parsing!)
- Parsing configs existed in conf.d/ but were never loaded by Logstash
- v3.0.3 embeds full parser directly into main.conf
- NEW deployments work immediately - no hotfixes needed
- Parses: beacon logs, events, weblogs, downloads, keystrokes, screenshots
- Compatible with official RedELK Filebeat field structure

**Git Tag**: `v3.0.3`
**Commit**: TBD

#### v3.0.2 (2025-10-26)
**Incomplete Fix** - Field structure updated but parsing still not working

Fixed field references in conf.d/ files (but they weren't being loaded):
- Updated Logstash parser to use official RedELK field structure
- Changed from flat `[fields][logtype]` to nested `[infra][log][type]`
- However: These files in conf.d/ were never loaded by Logstash!
- Dashboards still empty on deployed systems

**Git Tag**: `v3.0.2`
**Commit**: 5fcec1e

#### v3.0.1 (2025-10-26)
**Production Hardening Release**

Critical fixes for reliability and compatibility:
- Fixed Logstash authentication (API key → basic auth with hardcoded password)
- Fixed Logstash healthcheck (container logs instead of unavailable API port)
- Extended all service timeouts (ES 6min, Logstash 6min, Kibana 10min)
- Dashboard import with fail-fast error handling
- Filebeat cleanup on deployment
- Flexible Cobalt Strike path support

**Git Tag**: `v3.0.1`
**Commit**: 89b580a

#### v3.0.0 (2025-10-25)
**Initial Release**

Complete RedELK v3.0 implementation:
- Elastic Stack 8.15.3 (Elasticsearch, Logstash, Kibana)
- Ubuntu 20.04/22.04/24.04 support
- Docker Compose deployment
- Cobalt Strike and PoshC2 support
- Apache, Nginx, HAProxy redirector support
- RedELK dashboards and visualizations

**Git Tag**: `v3.0.0`

## Version Tracking

The current version is stored in the [VERSION](VERSION) file at the repository root.

## Release Process

1. **Development**: Work on features/fixes in feature branches
2. **Testing**: Verify deployment on Ubuntu 20.04/22.04/24.04
3. **Documentation**: Update [CHANGELOG.md](CHANGELOG.md) with all changes
4. **Version Bump**: Update [VERSION](VERSION) file
5. **Git Tag**: Create annotated git tag matching version
6. **Release**: Push commits and tags to GitHub
7. **Deployment Bundle**: Rebuild `redelk-v3-deployment.tar.gz`

### Creating a Release

```bash
# Example for v3.0.2 patch release
echo "3.0.2" > VERSION
git add VERSION CHANGELOG.md
git commit -m "Release v3.0.2: Brief description"
git tag -a v3.0.2 -m "v3.0.2 - Brief description of changes"
git push origin master
git push origin v3.0.2
```

## Version Compatibility

### Elastic Stack Versions
- RedELK v3.0.x → Elastic Stack 8.15.x
- RedELK v3.1.x → Elastic Stack 8.16.x (future)
- RedELK v4.x.x → Elastic Stack 9.x (future)

### Operating System Support
- Ubuntu 24.04 LTS (Noble Numbat) - Recommended
- Ubuntu 22.04 LTS (Jammy Jellyfish) - Supported
- Ubuntu 20.04 LTS (Focal Fossa) - Supported

### C2 Framework Support
- Cobalt Strike 4.0+
- PoshC2 (all recent versions)
- Sliver (planned for v3.1.0)
- Havoc (planned for v3.2.0)

## Upgrade Paths

### Patch Upgrades (e.g., 3.0.0 → 3.0.1)
- Simple redeployment with new script
- No data migration needed
- Existing indices preserved
- May require Filebeat redeployment on C2 servers

### Minor Upgrades (e.g., 3.0.x → 3.1.0)
- New features available immediately
- Existing configurations remain valid
- Optional: Adopt new features
- No breaking changes

### Major Upgrades (e.g., 3.x → 4.x)
- Review migration guide in CHANGELOG
- Backup existing data before upgrade
- May require configuration changes
- Test in staging environment first

## Support Policy

- **Current PATCH version**: Full support with bug fixes
- **Previous PATCH versions**: Security fixes only
- **MINOR versions**: Supported for 6 months after next MINOR release
- **MAJOR versions**: Supported for 12 months after next MAJOR release

## Deprecation Policy

Features scheduled for removal will be:
1. Marked as deprecated in documentation
2. Logged with warning messages when used
3. Removed in the next MAJOR version

Minimum deprecation period: 3 months for MINOR features, 6 months for MAJOR features.

---

**Current Stable Release**: v3.0.1
**Release Date**: 2025-10-26
**Tested On**: Ubuntu 24.04.3 LTS, Docker 28.5.1, Elastic Stack 8.15.3
