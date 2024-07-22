HOST_IP ?= 192.168.18.18

.PHONY: deploy
deploy:
	oc new-project unix-socket || true
	oc create serviceaccount unix-socket || true
	oc label ns unix-socket pod-security.kubernetes.io/enforce=privileged --overwrite=true
	oc adm policy add-scc-to-user privileged -z unix-socket
	oc apply -f server.yaml
	oc apply -f client.yaml

.PHONY: deploy-with-profile
deploy-with-profile:
	oc new-project unix-socket || true
	oc create serviceaccount unix-socket || true
	oc label ns unix-socket pod-security.kubernetes.io/enforce=privileged --overwrite=true
	oc adm policy add-scc-to-user privileged -z unix-socket
	oc apply -f server-with-profile.yaml
	oc apply -f client-with-profile.yaml

.PHONY: undeploy
undeploy:
	oc project default
	oc delete project unix-socket

# SPO installation:    https://docs.openshift.com/container-platform/4.14/security/security_profiles_operator/spo-enabling.html
# Enable log enricher: https://docs.openshift.com/container-platform/4.14/security/security_profiles_operator/spo-advanced.html#spo-log-enricher_spo-advanced
.PHONY: install-spo
install-spo:
	oc apply -f spo.yaml
	sleep 180
	oc -n openshift-security-profiles patch spod spod --type=merge -p '{"spec":{"verbosity":1}}'
	oc -n openshift-security-profiles patch spod spod --type=merge -p '{"spec":{"enableLogEnricher":true}}'

.PHONY: uninstall-spo
uninstall-spo:
	oc delete -f spo.yaml

# NOTE: Empty the audit log of the node before:
# > /var/log/audit/audit.log
# And delete the SPO pod:
#  oc delete pod -n openshift-security-profiles -l name=spod
# (I saw issues when running the SPO profiler and that fixed them)
.PHONY: reset-spo
reset-spo:
	ssh core@$(HOST_IP) bash -c "echo '' | sudo tee /var/log/audit/audit.log"
	oc delete pod -n openshift-security-profiles -l name=spod
	oc wait pods -n openshift-security-profiles -l name=spod --for=condition=Ready --timeout=120s

.PHONY: tail-spo-logs
tail-spo-logs:
	oc logs -n openshift-security-profiles -l name=spod --all-containers --tail=-1 --max-log-requests=10 -f

# Using the profile recorder: https://docs.openshift.com/container-platform/4.14/security/security_profiles_operator/spo-selinux.html#spo-recording-profiles_spo-selinux
.PHONY: start-profile-recording-server
start-profile-recording-server:
	oc delete -f server.yaml --wait=true || true
	oc label ns unix-socket spo.x-k8s.io/enable-recording=true
	sleep 5
	oc apply -f profile-recording-server.yaml
	sleep 10
	oc apply -f server.yaml
	sleep 15
	oc delete -f server.yaml --wait=true
	sleep 10

.PHONY: stop-profile-recording-server
stop-profile-recording-server:
	oc delete -f profile-recording-server.yaml
	oc label ns unix-socket spo.x-k8s.io/enable-recording-


# Using the profile recorder: https://docs.openshift.com/container-platform/4.14/security/security_profiles_operator/spo-selinux.html#spo-recording-profiles_spo-selinux
.PHONY: start-profile-recording-client
start-profile-recording-client:
	oc delete -f client.yaml --wait=true || true
	oc label ns unix-socket spo.x-k8s.io/enable-recording=true
	sleep 5
	oc apply -f profile-recording-client.yaml
	sleep 10
	oc apply -f client.yaml
	sleep 15
	oc delete -f client.yaml --wait=true
	sleep 10

.PHONY: stop-profile-recording-client
stop-profile-recording-client:
	oc delete -f profile-recording-client.yaml
	oc label ns unix-socket spo.x-k8s.io/enable-recording-

