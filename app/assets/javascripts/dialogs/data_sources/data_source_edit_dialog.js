chorus.dialogs.DataSourceEdit = chorus.dialogs.Base.extend({
    constructorName: "DataSourceEdit",

    templateName: "data_source_edit",
    title: t("data_sources.edit_dialog.title"),
    events: {
        "submit form": "save",
        "click a.connection_parameters": "launchConnectionParametersDialog",
        "change input[name=high_availability]": 'toggleHighAvailability'
    },

    formFields: ["name", "host", "port", "size", "dbName", "username", "groupList", "streamUrl", "password", "jobTrackerHost", "jobTrackerPort", "hdfsVersion"],

    makeModel: function() {
        this.sourceModel = this.model;
        this.model = this.model.clone();
        this.listenTo(this.model, 'change', this.rewriteLink);
    },

    setup: function() {
        this.listenTo(this.model, "saved", this.saveSuccess);
        this.listenTo(this.model, "saveFailed", this.saveFailed);
        this.listenTo(this.model, "validationFailed", this.saveFailed);
    },

    postRender: function() {
        this.$(".hdfs_version").val(this.model.get("hdfsVersion"));
        _.defer(_.bind(function() {
            chorus.styleSelect(this.$("select.hdfs_version"), { format: function(text, option) {
                var aliasedName = $(option).attr("name");
                return '<span class='+ aliasedName +'></span>' + text;
            } });
        }, this));
    },

    launchConnectionParametersDialog: function (e) {
        e && e.preventDefault();

        new chorus.dialogs.HdfsConnectionParameters({model: this.model}).launchModal();
    },

    rewriteLink: function () {
        this.$('a.connection_parameters').text(t('data_sources.dialog.connection_parameters', {count: this.model.numberOfConnectionParameters()}));
    },

    toggleHighAvailability: function (e) {
        e && e.preventDefault();

        if (this.$('input[name=high_availability]').prop('checked')) {
            this.$('input[name=port]').val('');
            this.$('[name=port]').prop('disabled', true).removeClass('required');
            this.$('label[name=host]').text(t('data_sources.dialog.name_service'));
        } else {
            this.$('[name=port]').prop('disabled', false).addClass('required');
            this.$('label[name=host]').text(t('data_sources.dialog.hadoop_host'));
        }
    },

    additionalContext: function() {
        return {
            gpdbDataSource: this.model.isGreenplum(),
            gpdbOrOracleDataSource: this.model.isGreenplum() || this.model.isOracle(),
            jdbcDataSource: this.model.isJdbc(),
            hdfsDataSource: this.model.constructorName === "HdfsDataSource",
            gnipDataSource: this.model.constructorName === "GnipDataSource",
            parameterCount: {count: this.model.numberOfConnectionParameters()}
        };
    },

    save: function(e) {
        e.preventDefault();
        var attrs = {
            description: this.$("textarea[name=description]").val().trim()
        };

        _.each(this.formFields, function(name) {
            var input = this.$("input[name=" + name + "], select[name=" + name + "]");
            if (input.length) {
                attrs[name] = input.val().trim();
            }
        }, this);

        attrs.highAvailability = !!this.$("input[name=high_availability]").prop("checked");
        attrs.ssl = !!this.$("input[name=ssl]").prop("checked");

        this.$("button.submit").startLoading("data_sources.edit_dialog.saving");
        this.$("button.cancel").prop("disabled", true);
        this.model.save(attrs, {silent: true});
    },

    saveSuccess: function() {
        this.sourceModel.set(this.model.attributes);
        chorus.toast("data_sources.edit_dialog.saved_message");
        this.closeModal();
    }
});
