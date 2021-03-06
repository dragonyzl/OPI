/* OPI: Orbital Propagation Interface
 * Copyright (C) 2014 Institute of Aerospace Systems, TU Braunschweig, All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3.0 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library.
 */
#include "opi_host.h"
#include "internal/opi_plugin.h"
#include "opi_propagator.h"
#include "internal/opi_cudasupport.h"
#include "internal/opi_propagator_plugin.h"
#include "internal/opi_query_plugin.h"
#include "opi_custom_propagator.h"
#include "opi_collisiondetection.h"
#include "internal/dynlib.h"
#include <iostream>
#ifdef _MSC_VER
#include "internal/msdirent.h"
#else
// mingw should have dirent
#include <dirent.h>
#endif
namespace OPI
{
	//! \cond INTERNAL_DOCUMENTATION

	class HostImpl
	{
		public:
			CudaSupport* cudaSupport;
			DynLib* cudaSupportPluginHandle;

			std::vector<Plugin*> pluginlist;
			std::vector<Propagator*> propagagorlist;
			std::vector<PerturbationModule*> modulelist;
			std::vector<PropagatorIntegrator*> integratorlist;
			std::vector<DistanceQuery*> querylist;
			std::vector<CollisionDetection*> detectionlist;
			OPI_ErrorCallback errorCallback;
			void* errorCallbackParameter;
			mutable ErrorCode lastError;
	};

	//! \endcond

	Host::Host()
	{
		impl->errorCallback = 0;
		impl->lastError = SUCCESS;
		impl->errorCallbackParameter = 0;

		impl->cudaSupport = 0;
		impl->cudaSupportPluginHandle = 0;
	}
	Host::~Host()
	{
		// free every propagator
		for(size_t i = 0; i < impl->propagagorlist.size(); ++i)
		{
			impl->propagagorlist[i]->disable();
			delete impl->propagagorlist[i];
		}

		for(size_t i = 0; i < impl->querylist.size(); ++i)
		{
			impl->querylist[i]->disable();
			delete impl->querylist[i];
		}

		for(size_t i = 0; i < impl->detectionlist.size(); ++i)
		{
			impl->detectionlist[i]->disable();
			delete impl->detectionlist[i];
		}

		// now free the support plugin memory
		if(impl->cudaSupport)
			impl->cudaSupport->shutdown();
		delete impl->cudaSupport;
		delete impl->cudaSupportPluginHandle;

		// free all plugin handles
		for(size_t i = 0; i < impl->pluginlist.size(); ++i)
			delete impl->pluginlist[i];

	}

	void Host::setErrorCallback(OPI_ErrorCallback callback, void* privatedata)
	{
		impl->errorCallback = callback;
		impl->errorCallbackParameter = privatedata;
	}

	ErrorCode Host::getLastError() const
	{
		return impl->lastError;
	}

	ErrorCode Host::loadPlugins(const std::string &plugindir)
	{
		ErrorCode status = SUCCESS;
		std::cout << "Loading plugins from " << plugindir << std::endl;

		// check if the cuda support plugin is loaded
		if(impl->cudaSupport == 0)
		{
			// try to load cuda plugin
			std::string libraryFileName = std::string(plugindir + "/support/OPI-cuda" + DynLib::getSuffix());
			impl->cudaSupportPluginHandle = new DynLib(libraryFileName);
			if(impl->cudaSupportPluginHandle)
			{
				procCreateCudaSupport proc_create_support = (procCreateCudaSupport)impl->cudaSupportPluginHandle->loadFunction("createCudaSupport");
				if(proc_create_support)
				{
					// plugin successfully loaded
					impl->cudaSupport = proc_create_support();
					impl->cudaSupport->init();
				}
				else {
					std::cout << "[OPI] Unable to load CUDA support library." << std::endl;
				}
			}
			else {
				std::cout << "[OPI] Cannot find CUDA support library (" << libraryFileName << ")"<< std::endl;
			}
		}

		// now load all plugins from plugindir
		DIR* dir = opendir(plugindir.c_str());
		// check if plugindir is a directory
		if(dir != 0)
		{
			dirent* dir_entry = 0;
			// iterate over all directory entries
			while((dir_entry = readdir(dir)))
			{
				std::string entry_name(dir_entry->d_name);
				// skip a few names
				if((entry_name != ".")&&(entry_name != "..") && (entry_name != "support"))
				{
					// try to load the plugin
					DynLib* lib = new DynLib(plugindir + "/" + entry_name);
					if(lib->isValid()) {
						// if it is valid load the plugin
						Plugin* plugin = new Plugin(lib);
						impl->pluginlist.push_back(plugin);
						loadPlugin(plugin);
					}
					else
						delete lib;
				}
			}
			// close the directory handle
			closedir(dir);
		}
		else
		{
			status = DIRECTORY_NOT_FOUND;
		}

		// forward the error message
		sendError(status);
		return status;
	}

	void Host::loadPlugin(Plugin *plugin)
	{
		// we have a functional plugin loaded
		// now create the correct type for it
		switch(plugin->getInfo().type)
		{
			// propagator plugin
			case OPI_PROPAGATOR_PLUGIN:
			{
				Propagator* propagator = 0;
				// this plugin uses the cpp interface
				if(plugin->getInfo().cppPlugin) {
					pluginPropagatorFunction proc_create = (pluginPropagatorFunction)plugin->getHandle()->loadFunction("OPI_Plugin_createPropagator");
					if(proc_create)
						propagator = proc_create(this);
				}
				// c plugin interface
				else
					propagator = new PropagatorPlugin(plugin);
				// if the propagator was created, add it to the list

				if(propagator) {
					if (propagator->requiresCUDA() <= 0) {
						addPropagator(propagator);
					}
					else if (!hasCUDASupport()) {
						std::cout << "[OPI] Skipping propagator " << propagator->getName()
							<< " because it requires CUDA." << std::endl;
					}
					else if (getCurrentCudaDeviceCapability() <= 0) {
						std::cout << "[OPI] Warning: Cannot determine CUDA compute capability of selected device "
							<< "(perhaps no CUDA device was selected?). " << std::endl;
						std::cout << "[OPI] Propagator " << propagator->getName() << " requires at least " 
							<< propagator->requiresCUDA() << ".x - "
							<< "otherwise propagation might fail." << std::endl;
						addPropagator(propagator);
					}
					else if (propagator->requiresCUDA() <= getCurrentCudaDeviceCapability()) {
						addPropagator(propagator);
					}
					else {
						std::cout << "[OPI] Skipping propagator " << propagator->getName()
							<< " because selected device is not capable of running it." << std::endl;
						std::cout << "[OPI] Device has compute capability " << getCurrentCudaDeviceCapability() << ", "
							<< propagator->getName() << " requires at least " << propagator->requiresCUDA() << "."
							<< std::endl;
					}
				}
				break;
			}
			// a distance query plugin
			case OPI_DISTANCE_QUERY_PLUGIN:
			{
				DistanceQuery* query = 0;
				// this plugin uses the cpp interface
				if(plugin->getInfo().cppPlugin) {
					pluginDistanceQueryFunction proc_create = (pluginDistanceQueryFunction)plugin->getHandle()->loadFunction("OPI_Plugin_createDistanceQuery");
					if(proc_create)
						query = proc_create(this);
				}
				// if the query plugin is valid, add it to the list
				if(query)
					addDistanceQuery(query);
				break;
			}
			// a collison detection plugin
			case OPI_COLLISION_DETECTION_PLUGIN:
			{
				CollisionDetection* cppplugin = 0;
				// this plugin uses the cpp interface
				if(plugin->getInfo().cppPlugin) {
					pluginCollisionDetectionFunction proc_create = (pluginCollisionDetectionFunction)plugin->getHandle()->loadFunction("OPI_Plugin_createCollisionDetection");
					if(proc_create)
						cppplugin = proc_create(this);
				}
				// if the plugin is valid, add it to the corresponding list
				if(cppplugin)
					addCollisionDetection(cppplugin);
				break;
			}
			// unknown/ not implemented plugin types
			default:
				std::cout << "[OPI] Unknown Plugin Type: " << plugin->getInfo().name << plugin->getInfo().type << std::endl;
		}
	}

	Propagator* Host::getPropagator(const std::string& name) const
	{
		for(size_t i = 0; i < impl->propagagorlist.size(); ++i)
		{
			if(impl->propagagorlist[i]->getName() == name)
				return impl->propagagorlist[i];
		}
		return 0;
	}

	Propagator* Host::getPropagator(int index) const
	{
		if((index < 0)||(index >= static_cast<int>(impl->propagagorlist.size())))
		{
			sendError(INDEX_RANGE);
			return 0;
		}
		return impl->propagagorlist[index];
	}

	int Host::getPropagatorCount() const
	{
		return static_cast<int>(impl->propagagorlist.size());
	}

	int Host::getCudaDeviceCount() const
	{
		if(!impl->cudaSupport)
			return 0;
		return impl->cudaSupport->getDeviceCount();
	}
	
	int Host::selectCudaDevice(int deviceNumber) const
	{
		if(!impl->cudaSupport) {
			return -1;
		}
		else {
			impl->cudaSupport->selectDevice(deviceNumber);
			return 0;
		}
	}

	std::string Host::getCurrentCudaDeviceName() const
	{
		if(!impl->cudaSupport) {
			return std::string("No CUDA device available.");
		}
		return impl->cudaSupport->getCurrentDeviceName();
	}

	int Host::getCurrentCudaDeviceCapability() const
	{
		if(!impl->cudaSupport) {
			return 0;
		}
		return impl->cudaSupport->getCurrentDeviceCapability();
	}

	void Host::addPropagator(Propagator *propagator)
	{
		propagator->setHost(this);
		impl->propagagorlist.push_back(propagator);
	}

	void Host::addDistanceQuery(DistanceQuery *query)
	{
		query->setHost(this);
		impl->querylist.push_back(query);
	}

	int Host::getDistanceQueryCount() const
	{
		return impl->querylist.size();
	}

	void Host::addCollisionDetection(CollisionDetection *module)
	{
		module->setHost(this);
		impl->detectionlist.push_back(module);
	}

	CollisionDetection* Host::getCollisionDetection(const std::string& name) const
	{
		for(size_t i = 0; i < impl->detectionlist.size(); ++i)
		{
			if(impl->detectionlist[i]->getName() == name)
				return impl->detectionlist[i];
		}
		return 0;
	}

	CollisionDetection* Host::getCollisionDetection(int index) const
	{
		if((index < 0)||(index >= static_cast<int>(impl->detectionlist.size())))
		{
			sendError(INDEX_RANGE);
			return 0;
		}
		return impl->detectionlist[index];
	}

	int Host::getCollisionDetectionCount() const
	{
		return impl->detectionlist.size();
	}

	bool Host::hasCUDASupport() const
	{
		if(impl->cudaSupport)
			return getCudaDeviceCount() > 0;
		return false;
	}

	DistanceQuery* Host::getDistanceQuery(const std::string& name) const
	{
		for(size_t i = 0; i < impl->querylist.size(); ++i)
		{
			if(impl->querylist[i]->getName() == name)
				return impl->querylist[i];
		}
		return 0;
	}

	DistanceQuery* Host::getDistanceQuery(int index) const
	{
		if((index < 0)||(index >= static_cast<int>(impl->querylist.size())))
		{
			sendError(INDEX_RANGE);
			return 0;
		}
		return impl->querylist[index];
	}

	CustomPropagator* Host::createCustomPropagator(const std::string& name)
	{
		CustomPropagator* prop = new CustomPropagator(name);
		addPropagator(prop);
		return prop;
	}

	/**
	 * \cond INTERNAL_DOCUMENTATION
	 */
	CudaSupport* Host::getCUDASupport() const
	{
		return impl->cudaSupport;
	}


	void Host::sendError(ErrorCode code) const
	{
		if(code != SUCCESS)
		{
			if(impl->errorCallback)
				impl->errorCallback((void*)(this), code, impl->errorCallbackParameter);
			impl->lastError = code;
		}
	}

	cudaDeviceProp* Host::getCUDAProperties(int device) const
	{
		if(impl->cudaSupport)
			return impl->cudaSupport->getDeviceProperties(device);
		return 0;
	}

	/**
	 * \endcond
	 */
}
