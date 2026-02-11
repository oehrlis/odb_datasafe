# Issue Title: Develop script to update On-Premises Connector

### Description
Develop a new script to update the Oracle Data Safe on-premises connector.

### Requirements
- Use existing scripts as a reference.
- Add a **dry run mode**.
- Allow the specification of Oracle Data Safe base or install directory.
- Accept OCI name/ID of the connector as input parameter or retrieve from `oradba_homes.conf` (e.g., description field formatted as `oci=name/id`).
- Generate a temporary bundle password, store it in `/etc/<name>_pwd.b64`, and reuse it if it already exists.

### Update Process
The process to update the connector includes:
1. Downloading the install bundle from the On-Premises Connector details page in the Oracle Data Safe service.
2. Uploading the bundle to the host where the connector is to be updated.
3. Unzipping the bundle into the directory where the on-premises connector is installed. This overwrites the existing files.
4. Running `setup.py` with the `update` argument (run as a non-root user):
   ```
   $ python setup.py update
   ```
5. Entering the bundle password when prompted.

**Note**: During the update, the connector cannot connect to target databases, but connections are re-established after the update is complete.

### Additional Notes
- Follow the documented procedure for updating an Oracle Data Safe On-Premises Connector.