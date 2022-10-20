## nora-wos

Harvest and process Web of Science (WoS) and Incites data.

### Requirements

To build the debian package you will need the following package:
* make
* devscripts
* debhelper

You can build the package by running:
* perl Makefile.PL
* make debian

### Running nora-wos (data backend)

Backup database before update:
* `$ nora-wos system backup`

Update WoS data (on the 19th of each month):
* `$ nora-wos update danish-records`
     
Generate DOI/orgs file (after WoS update):
* `$ nora-wos generate orgs-doi`

Update Incites indicators (end of month, see https://incites.help.clarivate.com/Content/dataset-updates.htm)
* `$ nora-wos nora-wos fetch indicators`

### Running nora-wos (VIVO side)

Generate RDF (after Incites update):
* `$ nora-wos rdf generate`
