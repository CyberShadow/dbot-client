import core.thread;

import std.exception;
import std.getopt;
import std.path;
import std.process;
import std.stdio;
import std.string;

import ae.sys.d.manager;
import ae.sys.file;
import ae.utils.array;
import ae.utils.json;

static import ae.sys.net.ae;

import dbot.config;
import dbot.protocol;

class TestDManager : DManager
{
	this()
	{
		config.local.workDir = "work".absolutePath();
		config.local.workDir.ensurePathExists();
		config.local.cache = "git";
	}

	override void log(string line)
	{
		sendLog(Message.Log.Type.log, line);
	}

	override string getCallbackCommand() { assert(false); } // Not needed in this program
}

void sendLog(Message.Log.Type type, string text)
{
	Message message = { type : Message.Type.log, log : { type : type, text : text } };
	sendMessage(message);
}

void sendProgress(Message.Progress.Type type)
{
	Message message = { type : Message.Type.progress, progress : { type : type } };
	sendMessage(message);
}

void sendMessage(ref Message message)
{
	stdout.writeln("dbot-client: ", message.toJson());
	stdout.flush();
}

int main(string[] args)
{
	try
	{
		string clientId;
		string[] fetchList, mergeList;

		getopt(args,
			"id", &clientId,
			"fetch", &fetchList,
			"merge", &mergeList,
		);

		enforce(args.length == 2, "Expected one non-option argument (base commit)");
		auto base = args[1];

		enforce(clientId, "Client ID not specified!");

		auto d = new TestDManager;

		sendProgress(Message.Progress.Type.fetch);

		// To avoid race conditions, we use the SHA1s from the command line.
		// We only pull these (and throw away the result) so that we have said SHAs
		// (in lieu of git/github providing a way to fetch a SHA1 directly).
		foreach (fetchItem; fetchList)
		{
			string submoduleName, remote, refString;
			list(submoduleName, remote, refString) = fetchItem.split('|');
			d.getSubmodule(submoduleName).getRemoteRef(remote, refString, "FETCH_HEAD");
		}

		sendProgress(Message.Progress.Type.merge);

		auto submoduleState = d.begin(base);

		foreach (mergeItem; mergeList)
		{
			string submoduleName, branch;
			list(submoduleName, branch) = mergeItem.split('|');
			d.merge(submoduleState, submoduleName, branch);
		}

		sendProgress(Message.Progress.Type.build);

		foreach (componentName; d.allComponents)
			d.config.build.components.enable[componentName] = shouldBuild(clientId, componentName);

		d.build(submoduleState);

		sendProgress(Message.Progress.Type.test);

		foreach (componentName; d.allComponents)
			d.config.build.components.enable[componentName] = shouldTest(clientId, componentName);

		d.test();

		sendProgress(Message.Progress.Type.bench);

		// TODO: benchmarks

		sendProgress(Message.Progress.Type.done);

		return 0;
	}
	catch (Exception e)
	{
		sendLog(Message.Log.Type.error, e.toString());
		return 1;
	}
}
